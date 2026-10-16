import Foundation
import Observation
import CoreModels
import CoreUI
import CoreNetworking
import ProviderPlex

/// The Plex Home users ("Who's watching?") facet, extracted from `AppState`.
///
/// Owns the in-memory Plex Home-user identity: per-account auth-token overrides
/// and their credential revisions, the resolved-home-user map, the unprotected-
/// token cache, the PIN-prompt state, and the "which Plex user are you?" onboarding
/// selection. It drives switching the active profile's Plex identity across every
/// signed-in Plex account (unprotected switches happen silently; the first
/// protected one raises a PIN prompt).
///
/// It depends INTO the `AccountsProvidersModel` hub via that hub's typed interface
/// (account store, device id, accounts, registry invalidation) — which is why the
/// hub was extracted first — plus the shared `ProfilesModel` and a `switchProfile`
/// callback for the PIN-cancel fallback. Kept `@MainActor @Observable` so the PIN
/// state and `plexIdentityGeneration` observation is identical to when it lived on
/// `AppState`.
@MainActor
@Observable
public final class PlexHomeUsersModel {
    /// Context for the "Which Plex user are you?" onboarding step.
    public struct PendingPlexUserSelection: Equatable, Identifiable, Sendable {
        public let accountID: String
        public let serverName: String
        public let users: [PlexHomeUser]
        /// Plex accounts from the same sign-in batch that should receive the
        /// selected Home-user binding.
        public let applyToAccountIDs: [String]
        /// Whether this selection is happening during a brand-new-install first
        /// run (drives whether we continue to profile-setup or the app).
        public let isFirstRun: Bool
        public var id: String { accountID }

        public init(
            accountID: String,
            serverName: String,
            users: [PlexHomeUser],
            isFirstRun: Bool,
            applyToAccountIDs: [String]? = nil
        ) {
            self.accountID = accountID
            self.serverName = serverName
            self.users = users
            self.isFirstRun = isFirstRun
            self.applyToAccountIDs = applyToAccountIDs ?? [accountID]
        }
    }

    /// A profile activation waiting on a Plex Home user's PIN.
    public struct PlexPINRequest: Identifiable, Equatable, Sendable {
        /// The id of the profile being activated.
        public let id: String
        public let accountID: String
        public let homeUserID: String
        public let homeUserName: String
        /// Optional Plex thumb URL for the Home user — used by the PIN
        /// dialog to render the real avatar above the keypad, like Plex's
        /// own tvOS PIN screen.
        public let homeUserAvatarURL: String?

        public init(
            id: String,
            accountID: String,
            homeUserID: String,
            homeUserName: String,
            homeUserAvatarURL: String? = nil
        ) {
            self.id = id
            self.accountID = accountID
            self.homeUserID = homeUserID
            self.homeUserName = homeUserName
            self.homeUserAvatarURL = homeUserAvatarURL
        }
    }

    /// A pending Plex PIN prompt, raised when activating a profile mapped to a
    /// PIN-protected Plex Home user. `RootView` presents an entry sheet bound to
    /// this; `nil` when no prompt is outstanding.
    public private(set) var pendingPlexPINRequest: PlexPINRequest?
    /// A wrong/failed-PIN message shown in the entry sheet, or `nil`.
    public private(set) var plexPINError: LocalizedStringResource?
    public private(set) var isSubmittingPlexPIN = false
    public private(set) var plexPINEntryAvailability: PINEntryAvailability = .checking
    /// Bumped whenever the active Plex identity (token override) changes so
    /// `RootView` rebuilds the signed-in subtree and content reloads as the new
    /// Plex Home user.
    public private(set) var plexIdentityGeneration = 0
    /// A pending "Which Plex user are you?" step, populated after a Plex account
    /// with 2+ Home users signs in (and this profile hasn't bound one yet).
    /// `RootView` presents the picker bound to this; `nil` when none is pending.
    public private(set) var pendingPlexUserSelection: PendingPlexUserSelection?

    /// A PIN entered to unlock a Plozz profile whose lock the user linked to
    /// their Plex PIN, waiting to be spent on that profile's next Plex
    /// Home-user switch so they're only asked once. Never persisted, never
    /// logged, and dropped after a single read — see
    /// `prefillPlexPIN(_:forProfile:)`.
    @ObservationIgnored
    private var prefilledPlexPIN: (profileID: String, pin: String)?

    private struct CredentialSource: Equatable {
        let provider: ProviderKind
        let revision: CredentialRevision
        let serverIdentity: String
        let userID: String

        init(_ account: Account) {
            provider = account.server.provider
            revision = account.credentialRevision
            serverIdentity = account.server.identityKey
            userID = account.userID
        }
    }

    private struct PINRequirementContext: Equatable {
        let request: PlexPINRequest
        let profile: AutomaticSignInStore.Session.ProfileAccess
        let binding: PlexHomeUserBinding
        let selectionID: UUID?
        let credentialSource: CredentialSource
        let activation: Int
        let identityGeneration: Int
    }

    private struct PendingBindingChange {
        let id: UUID
        let request: PlexPINRequest
        let profile: AutomaticSignInStore.Session.ProfileAccess
        let previousBinding: PlexHomeUserBinding?
        let binding: PlexHomeUserBinding
        let credentialSource: CredentialSource
        let activation: Int
        let identityGeneration: Int
    }

    @ObservationIgnored
    private var pendingBindingChange: PendingBindingChange?

    @ObservationIgnored
    private var pinRequirementCheck: (context: PINRequirementContext, task: Task<Void, Never>)?

    /// Protected tokens stay in memory unless the device explicitly trusts its
    /// last session for automatic startup. Manual switches never read that session.
    @ObservationIgnored
    private var plexTokenOverrides: [String: String] = [:]
    /// The Home user's ACCOUNT-level plex.tv token per account.
    ///
    /// Separate from `plexTokenOverrides`, which holds the per-SERVER access
    /// token that PMS authorizes browsing with: plex.tv Discover — the watchlist
    /// — needs the account-level one, and given a server token answers 401/403.
    ///
    /// Held in the box rather than a dictionary beside it so there is exactly ONE
    /// copy. A parallel dict was how the clearing paths came to update one and not
    /// the other, leaving a previous identity's token readable.
    @ObservationIgnored
    public let plexDiscoverTokens = PlexDiscoverTokenBox()

    /// Per-account identity generation, bumped whenever THIS account's resolved
    /// Plex identity changes.
    ///
    /// Beside the global `plexIdentityGeneration` (which the watchlist reconciler
    /// keys on, and which must move for any identity change) because supersession
    /// is an account-level question: two in-flight switches on DIFFERENT accounts
    /// are both current, and arbitrating them with one shared counter rejects
    /// whichever finishes second, stranding that account on the owner's token.
    @ObservationIgnored
    private var plexAccountIdentityGenerations: [String: Int] = [:]

    /// Records that `accountID`'s identity changed: bumps its own generation and
    /// the global one together, so neither can be updated without the other.
    private func bumpIdentityGeneration(for accountID: String, site: String) {
        plexAccountIdentityGenerations[accountID, default: 0] += 1
        plexIdentityGeneration += 1
        PlozzLog.boot("genBump=\(self.plexIdentityGeneration) site=\(site) acct=\(accountID)")
        onIdentityChanged()
    }
    /// Runtime revision for the effective Plex Home-user credential. Owner
    /// credentials continue to use the account's persisted revision.
    @ObservationIgnored
    private var plexOverrideCredentialRevisions: [String: CredentialRevision] = [:]
    /// For each account, the Plex Home-user UUID its server/cloud credentials resolve to.
    /// Lets the reconciler tell an already-satisfied protected switch apart from a
    /// stale override left by a previous profile, so a just-entered PIN isn't
    /// re-armed into an infinite prompt/re-prompt loop.
    @ObservationIgnored
    private var plexResolvedHomeUser: [String: String] = [:]
    @ObservationIgnored
    private var plexPINVerifiedHomeUser: [String: String] = [:]
    @ObservationIgnored
    private var plexCredentialSources: [String: CredentialSource] = [:]
    /// Keychain-backed cache of resolved server tokens for **unprotected** Plex
    /// Home users. Lets `ensurePlexIdentityForActiveProfile` install the right
    /// identity synchronously at launch/profile-pick (instant, ungated paint),
    /// then refresh it in the background. PIN-protected users are never cached.
    @ObservationIgnored
    private let plexHomeUserTokenCache: PlexHomeUserTokenCache
    @ObservationIgnored private let automaticSignInStore: AutomaticSignInStore
    @ObservationIgnored private var didAttemptAutomaticSignIn = false
    @ObservationIgnored private var startupProfileAccess: AutomaticSignInStore.Session.ProfileAccess?
    @ObservationIgnored private var authenticatedProfileAccess: AutomaticSignInStore.Session.ProfileAccess?
    @ObservationIgnored private var profileActivationGeneration = 0
    public private(set) var automaticallySignIn: Bool
    public private(set) var automaticSignInError: LocalizedStringResource?

    /// The accounts + providers hub (typed). Read for the account store, device
    /// id, signed-in accounts, and per-account provider-cache invalidation.
    @ObservationIgnored
    private let accountsProviders: AccountsProvidersModel
    /// The household's profiles + active selection (shared reference).
    @ObservationIgnored
    private let profilesModel: ProfilesModel
    /// Switches the active profile — used by the PIN-cancel fallback so the UI is
    /// never left under a profile the user couldn't unlock. Injected because
    /// profile switching lives on `AppState` (profile-flow domain).
    @ObservationIgnored
    private let switchProfile: @MainActor (String) -> Void

    /// Switches to a Plex Home user, returning the new auth token. Injectable for
    /// tests; defaults to a live `PlexAuthClient` call.
    @ObservationIgnored
    var plexHomeUserSwitch: @Sendable (_ uuid: String, _ pin: String?, _ adminToken: String, _ deviceID: String) async throws -> String = { uuid, pin, adminToken, deviceID in
        try await PlexAuthClient(deviceProfile: PlexDeviceProfile(clientIdentifier: deviceID))
            .switchHomeUser(uuid: uuid, pin: pin, authToken: adminToken)
    }
    /// Lists a Plex account's Home users. Injectable for tests; defaults to a
    /// live `PlexAuthClient` call.
    @ObservationIgnored
    var plexHomeUsersFetch: @Sendable (_ adminToken: String, _ deviceID: String) async throws -> [PlexHomeUser] = { adminToken, deviceID in
        try await PlexAuthClient(deviceProfile: PlexDeviceProfile(clientIdentifier: deviceID))
            .homeUsers(authToken: adminToken)
    }
    /// Resolves the **server-scoped** access token for `serverID` from a Plex
    /// account/Home-user token, by asking plex.tv (`/api/v2/resources`) for that
    /// user's access to the server. Injectable for tests; defaults to a live
    /// `PlexAuthClient` call. Returns `nil` when the user has no access to the
    /// server (or the lookup fails), so callers can fall back to the raw token.
    @ObservationIgnored
    var plexServerTokenResolve: @Sendable (_ serverID: String, _ userToken: String, _ deviceID: String) async -> String? = { serverID, userToken, deviceID in
        let client = PlexAuthClient(deviceProfile: PlexDeviceProfile(clientIdentifier: deviceID))
        let servers = try? await client.servers(authToken: userToken)
        return servers?.first { $0.id == serverID }?.accessToken
    }

    public init(
        accountsProviders: AccountsProvidersModel,
        profilesModel: ProfilesModel,
        plexHomeUserTokenCache: PlexHomeUserTokenCache = .makeDefault(),
        automaticSignInStore: AutomaticSignInStore = .makeDefault(),
        switchProfile: @escaping @MainActor (String) -> Void,
        onIdentityChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.accountsProviders = accountsProviders
        self.profilesModel = profilesModel
        self.plexHomeUserTokenCache = plexHomeUserTokenCache
        self.automaticSignInStore = automaticSignInStore
        self.automaticallySignIn = automaticSignInStore.isEnabled
        self.switchProfile = switchProfile
        self.onIdentityChanged = onIdentityChanged
    }

    /// Called after the effective Plex identity changes.
    ///
    /// Switching "watching as" changes whose library, watch state and watchlist
    /// the app should be showing — but it changes neither the profile nor the
    /// account set, so none of the usual refresh triggers fire. Nothing observed
    /// `plexIdentityGeneration` either, so Home, Continue Watching and the
    /// watchlist all went on showing the previous user's world until the viewer
    /// switched profiles away and back, which was the only thing that moved the
    /// namespace. Announcing it is the fix.
    @ObservationIgnored
    private let onIdentityChanged: @MainActor () -> Void

    // MARK: Device-only automatic sign-in

    /// Called once by the shell, before it decides whether to show launch gates.
    @discardableResult
    public func restoreAutomaticSignInAtLaunch() -> Bool {
        guard !didAttemptAutomaticSignIn else { return false }
        didAttemptAutomaticSignIn = true
        guard automaticallySignIn else { return false }
        do {
            guard let session = try automaticSignInStore.load() else { return false }
            let profile = profilesModel.activeProfile
            let accounts = automaticSignInAccounts(for: profile)
            guard session.profile == .init(profile),
                  session.accounts == accounts,
                  !profile.needsSetup else {
                try automaticSignInStore.invalidate()
                return false
            }
            let boundAccounts = accounts.filter { $0.homeUserID != nil }
            guard Set(session.plexCredentials.keys) == Set(boundAccounts.map(\.id)),
                  session.plexCredentials.values.allSatisfy({
                      !$0.serverToken.isEmpty && !$0.discoverToken.isEmpty
                  }),
                  boundAccounts.allSatisfy({ account in
                      guard let binding = profile.homeUserBinding(forPlexAccount: account.id) else { return false }
                      return session.plexCredentials[account.id]?.pinVerified == true
                          || (binding.requiresPIN == false && binding.pinRequirementVerified == true)
                  }) else {
                try automaticSignInStore.invalidate()
                return false
            }
            // Validate the whole session before publishing any identity.
            for account in boundAccounts {
                guard let credential = session.plexCredentials[account.id] else { continue }
                setPlexTokenOverride(credential.serverToken, for: account.id)
                plexDiscoverTokens.setToken(credential.discoverToken, for: account.id)
                plexResolvedHomeUser[account.id] = account.homeUserID
                if let sourceAccount = accountsProviders.accounts.first(where: { $0.id == account.id }) {
                    plexCredentialSources[account.id] = CredentialSource(sourceAccount)
                }
                if credential.pinVerified == true {
                    plexPINVerifiedHomeUser[account.id] = account.homeUserID
                }
                accountsProviders.registry.invalidate(accountID: account.id)
            }
            startupProfileAccess = session.profile
            authenticatedProfileAccess = session.profile
            return true
        } catch {
            reportAutomaticSignInStorageError()
            return false
        }
    }

    public func isAutomaticallySignedIn(_ profile: Profile) -> Bool {
        if startupProfileAccess != .init(profile) {
            startupProfileAccess = nil
        }
        return startupProfileAccess == .init(profile)
    }

    public func setAutomaticallySignIn(_ enabled: Bool, profileIsUnlocked: Bool) {
        automaticSignInError = nil
        if enabled {
            guard profileIsUnlocked,
                  pendingPlexPINRequest == nil,
                  pendingPlexUserSelection == nil else {
                automaticSignInError = "Finish signing in to this profile before enabling automatic sign-in."
                return
            }
            authenticatedProfileAccess = .init(profilesModel.activeProfile)
            guard let session = automaticSignInSession() else {
                automaticSignInError = "Finish signing in to this profile before enabling automatic sign-in."
                return
            }
            do {
                try automaticSignInStore.enable(with: session)
                automaticallySignIn = true
            } catch {
                reportAutomaticSignInStorageError()
            }
        } else {
            automaticallySignIn = false
            do {
                try automaticSignInStore.disable()
            } catch {
                reportAutomaticSignInStorageError()
            }
        }
    }

    /// The shell calls this only after its local profile/parental gates succeed.
    public func beginExplicitProfileActivation() {
        profileActivationGeneration += 1
        startupProfileAccess = nil
        authenticatedProfileAccess = .init(profilesModel.activeProfile)
        clearPlexOverrides()
        invalidateAutomaticSignInSession()
    }

    private func automaticSignInAccounts(for profile: Profile) -> [AutomaticSignInStore.Session.AccountAccess] {
        accountsProviders.accounts
            .map { .init($0, profile: profile) }
            .sorted { $0.id < $1.id }
    }

    private func automaticSignInSession() -> AutomaticSignInStore.Session? {
        let profile = profilesModel.activeProfile
        guard !profile.needsSetup,
              !profile.isLocked || authenticatedProfileAccess == .init(profile) else { return nil }
        var credentials: [String: AutomaticSignInStore.Session.PlexCredential] = [:]
        for account in accountsProviders.accounts where account.server.provider == .plex {
            guard let binding = profile.homeUserBinding(forPlexAccount: account.id) else { continue }
            guard plexResolvedHomeUser[account.id] == binding.homeUserID,
                  plexCredentialSources[account.id] == CredentialSource(account),
                  let serverToken = plexTokenOverrides[account.id], !serverToken.isEmpty,
                  let discoverToken = plexDiscoverTokens.token(for: account.id), !discoverToken.isEmpty
            else { return nil }
            let pinVerified = plexPINVerifiedHomeUser[account.id] == binding.homeUserID
            guard pinVerified || (binding.requiresPIN == false && binding.pinRequirementVerified == true)
            else { return nil }
            credentials[account.id] = .init(
                serverToken: serverToken, discoverToken: discoverToken, pinVerified: pinVerified
            )
        }
        return .init(
            profile: .init(profile),
            accounts: automaticSignInAccounts(for: profile),
            plexCredentials: credentials
        )
    }

    private func rememberAutomaticSignInIfReady() {
        guard automaticallySignIn else { return }
        do {
            if let session = automaticSignInSession() {
                try automaticSignInStore.save(session)
            } else {
                try automaticSignInStore.invalidate()
            }
        } catch {
            reportAutomaticSignInStorageError()
        }
    }

    private func invalidateAutomaticSignInSession() {
        do {
            try automaticSignInStore.invalidate()
        } catch {
            reportAutomaticSignInStorageError()
        }
    }

    private func reportAutomaticSignInStorageError() {
        automaticallySignIn = false
        automaticSignInStore.blockRestoration()
        PlozzLog.auth.error("Automatic sign-in Keychain operation failed")
        automaticSignInError = "Couldn’t update automatic sign-in on this device. Try again."
    }

    // MARK: Token / credential resolution (the AccountsProviders hub seams)

    /// The auth token to use for `accountID`, preferring an in-memory Plex
    /// Home-user override over the account's stored (admin) token.
    public func resolvedToken(for accountID: String) -> String? {
        guard hasCurrentCredentialSource(for: accountID) else { return nil }
        return plexTokenOverrides[accountID] ?? accountsProviders.accountStore.token(for: accountID)
    }

    private func hasCurrentCredentialSource(for accountID: String) -> Bool {
        guard let source = plexCredentialSources[accountID] else { return true }
        return accountsProviders.accounts.first(where: { $0.id == accountID }).map(CredentialSource.init) == source
    }

    /// Watch outbox dispatch must wait for the selected viewer's actual server
    /// credential, not merely a profile binding that is still being activated.
    public func hasResolvedWatchMutationIdentity(forAccountID accountID: String) -> Bool {
        guard hasCurrentCredentialSource(for: accountID), accountsProviders.accounts.contains(where: {
            $0.id == accountID && $0.server.provider == .plex
        }) else { return false }
        if let binding = profilesModel.activeProfile.homeUserBinding(forPlexAccount: accountID) {
            return plexResolvedHomeUser[accountID] == binding.homeUserID
                && !(plexTokenOverrides[accountID]?.isEmpty ?? true)
        }
        return plexResolvedHomeUser[accountID] == nil && plexTokenOverrides[accountID] == nil
    }

    /// The effective credential revision for an account, using an override-scoped
    /// revision when a Plex Home-user override is active.
    public func effectiveCredentialRevision(for account: Account) -> CredentialRevision {
        guard account.server.provider == .plex,
              hasCurrentCredentialSource(for: account.id),
              plexTokenOverrides[account.id] != nil else {
            return account.credentialRevision
        }
        if let revision = plexOverrideCredentialRevisions[account.id] {
            return revision
        }
        let revision = CredentialRevision()
        plexOverrideCredentialRevisions[account.id] = revision
        return revision
    }

    /// Installs (or clears) the per-server token override for an account.
    ///
    /// Clearing also drops the account-level Discover token, because the two are
    /// one identity: leaving the Discover half behind let a profile that had
    /// switched to the owner — or to a different Home user — keep reading and
    /// writing the PREVIOUS user's watchlist, and made the fail-closed check
    /// pass on a token that no longer applied.
    private func setPlexTokenOverride(_ token: String?, for accountID: String) {
        if plexTokenOverrides[accountID] != token {
            plexOverrideCredentialRevisions[accountID] = token == nil
                ? nil
                : CredentialRevision()
        }
        plexTokenOverrides[accountID] = token
        if token == nil {
            plexDiscoverTokens.setToken(nil, for: accountID)
            plexPINVerifiedHomeUser[accountID] = nil
            plexCredentialSources[accountID] = nil
        }
    }

    // MARK: Plex Home users ("Who's watching?")

    /// Lists the Plex Home users for a signed-in Plex account (for the profile
    /// editor's "Plex User" picker). Returns `[]` for non-Plex/unknown accounts
    /// or on failure. Always uses the account's stored (admin) token.
    public func plexHomeUsers(forAccountID accountID: String) async -> [PlexHomeUser] {
        guard let account = accountsProviders.accounts.first(where: { $0.id == accountID }),
              account.server.provider == .plex,
              let adminToken = accountsProviders.accountStore.token(for: accountID) else { return [] }
        // Log a fetch failure instead of swallowing it silently — an empty picker
        // then reads as a real error, not indistinguishable from "no Home users".
        // Contract unchanged: still returns [] on failure.
        do {
            return try await plexHomeUsersFetch(adminToken, accountsProviders.deviceID)
        } catch {
            PlozzLog.auth.error("Plex Home-users fetch failed acct=\(accountID): \(error)")
            return []
        }
    }

    /// Authenticates a proposed Home-user change before saving or replacing the
    /// current identity. Cancelling the proposal leaves the saved binding intact.
    public func setPlexHomeUserForActiveProfile(accountID: String, user: PlexHomeUser?) {
        guard let account = accountsProviders.accounts.first(where: {
            $0.id == accountID && $0.server.provider == .plex
        }) else {
            PlozzLog.auth.error("Plex Home-user selection has no matching account")
            return
        }
        discardPendingBindingChange()
        let profile = profilesModel.activeProfile
        guard let user else {
            profilesModel.update(profile.settingHomeUserBinding(nil, forPlexAccount: accountID))
            ensurePlexIdentityForActiveProfile()
            return
        }
        let binding = PlexHomeUserBinding(
            homeUserID: user.id, name: user.name,
            avatarURL: user.avatarURL?.absoluteString, requiresPIN: user.requiresPIN,
            isManaged: user.isRestricted, pinRequirementVerified: user.pinRequirementVerified
        )
        if profile.homeUserBinding(forPlexAccount: accountID) == binding {
            ensurePlexIdentityForActiveProfile()
            return
        }
        // Supersede old refreshes without discarding the current user's credentials.
        plexAccountIdentityGenerations[accountID, default: 0] += 1
        let id = UUID()
        let request = Self.pinRequest(profileID: "\(profile.id)#\(id)", target: (accountID, binding))
        pendingBindingChange = PendingBindingChange(
            id: id, request: request, profile: .init(profile),
            previousBinding: profile.homeUserBinding(forPlexAccount: accountID), binding: binding,
            credentialSource: CredentialSource(account), activation: profileActivationGeneration,
            identityGeneration: plexAccountIdentityGenerations[accountID, default: 0]
        )
        pendingPlexPINRequest = request
        plexPINEntryAvailability = .checking
        plexPINError = nil
        checkPlexPINRequirement(for: request, suppliedPIN: nil)
    }

    private func isCurrentBindingChange(_ change: PendingBindingChange) -> Bool {
        pendingBindingChange?.id == change.id
            && change.profile == .init(profilesModel.activeProfile)
            && profilesModel.activeProfile.homeUserBinding(forPlexAccount: change.request.accountID) == change.previousBinding
            && accountsProviders.accounts.first(where: { $0.id == change.request.accountID }).map(CredentialSource.init)
                == change.credentialSource
            && profileActivationGeneration == change.activation
            && plexAccountIdentityGenerations[change.request.accountID, default: 0] == change.identityGeneration
    }

    private func discardPendingBindingChange() {
        guard let change = pendingBindingChange else { return }
        cancelPINRequirementCheck()
        pendingBindingChange = nil
        if pendingPlexPINRequest == change.request {
            pendingPlexPINRequest = nil
            plexPINEntryAvailability = .checking
            plexPINError = nil
        }
    }

    /// Submits a PIN for the outstanding Plex Home-user switch.
    public func submitPlexPIN(_ pin: String) {
        guard let request = pendingPlexPINRequest else { return }
        guard !pin.isEmpty else {
            plexPINError = ProfileLockCopy.incorrectPIN
            return
        }
        PlozzLog.auth.debug("submitPlexPIN len=\(pin.count) acct=\(request.accountID)")
        plexPINError = nil
        checkPlexPINRequirement(for: request, suppliedPIN: pin)
    }

    /// Cancels a proposed selection without changing the existing identity.
    /// An unresolved saved-profile activation instead keeps its authorization
    /// gate until the normal profile-switch flow authorizes a fallback.
    public func cancelPlexPIN() {
        guard pendingPlexPINRequest != nil else { return }
        if pendingBindingChange != nil {
            discardPendingBindingChange()
            ensurePlexIdentityForActiveProfile()
            return
        }
        let cancelledRequest = pendingPlexPINRequest
        let cancelledAvailability = plexPINEntryAvailability
        profileActivationGeneration += 1
        startupProfileAccess = nil
        authenticatedProfileAccess = nil
        invalidateAutomaticSignInSession()
        clearPlexOverrides()
        // Clearing credentials is not authorization. Keep the gate until a
        // fallback actually activates, including when its own lock is cancelled.
        pendingPlexPINRequest = cancelledRequest
        plexPINEntryAvailability = cancelledAvailability == .checking ? .unavailable : cancelledAvailability
        if let fallback = profilesModel.profiles.first?.id,
           fallback != profilesModel.activeProfileID {
            HandoffDiagnostics.emit(
                "profile PLEXPIN_CANCEL fallback=" + fallback
                    + " leaving=" + profilesModel.activeProfileID
            )
            switchProfile(fallback)
        }
    }

    /// Treats a programmatic sheet dismissal as a cancel **only** when a prompt
    /// is still outstanding (a successful switch already cleared it).
    public func dismissPlexPINIfPresented() {
        if pendingPlexPINRequest != nil { cancelPlexPIN() }
    }

    /// Aligns the in-memory Plex identity for **every** signed-in Plex account
    /// with the active profile's per-account Home-user bindings:
    /// - Unprotected bindings switch silently on each account.
    /// - The first protected binding (in account order) raises a PIN prompt;
    ///   subsequent ones are processed after the user submits or cancels.
    /// - An account with no binding drops any existing override for that
    ///   account (back to the admin user).
    public func ensurePlexIdentityForActiveProfile() {
        defer { rememberAutomaticSignInIfReady() }
        if let change = pendingBindingChange {
            if isCurrentBindingChange(change) { return }
            discardPendingBindingChange()
        }
        let profile = profilesModel.activeProfile
        if startupProfileAccess != .init(profile) {
            startupProfileAccess = nil
        }
        let plexAccounts = accountsProviders.accounts.filter { $0.server.provider == .plex }
        let boundCount = plexAccounts.filter { profile.homeUserBinding(forPlexAccount: $0.id) != nil }.count
        PlozzLog.boot("ensurePlexIdentity profile=\(profile.id) plexAccounts=\(plexAccounts.count) withBinding=\(boundCount) gen=\(self.plexIdentityGeneration)")

        // Take any stashed "same PIN as Plex" value for THIS profile up front, so
        // exactly one pass can ever see it. Reading it here rather than inside the
        // `pinTarget` branch matters: a profile with no protected binding would
        // otherwise leave the plaintext PIN sitting in memory for the rest of the
        // run, to be spent on some unrelated later pass (e.g. after the user links
        // a protected Home user in Settings).
        let prefilledPIN = consumePrefilledPIN(forProfile: profile.id)

        var pinTarget: (accountID: String, binding: PlexHomeUserBinding)?

        for account in plexAccounts {
            if let source = plexCredentialSources[account.id], source != CredentialSource(account) {
                setPlexTokenOverride(nil, for: account.id)
                plexResolvedHomeUser[account.id] = nil
                plexCredentialSources[account.id] = nil
                plexHomeUserTokenCache.removeAll(account: account.id)
                accountsProviders.registry.invalidate(accountID: account.id)
                bumpIdentityGeneration(for: account.id, site: "ensure.replacedCredential")
            }
            if let binding = profile.homeUserBinding(forPlexAccount: account.id) {
                if binding.requiresPIN != false || binding.pinRequirementVerified != true {
                    // The general switch cache must never unlock a protected user.
                    plexHomeUserTokenCache.remove(account: account.id, homeUser: binding.homeUserID)
                    // Already resolved to exactly this user? It's satisfied —
                    // leave it, don't re-prompt. (Was the source of the
                    // re-entrancy loop: success cleared the override, the
                    // reconciler immediately re-prompted, cover never tore down.)
                    if plexTokenOverrides[account.id] != nil,
                       plexResolvedHomeUser[account.id] == binding.homeUserID,
                       plexPINVerifiedHomeUser[account.id] == binding.homeUserID {
                        continue
                    }
                    // Stale override for a DIFFERENT user — drop before prompting.
                    if plexTokenOverrides[account.id] != nil || plexResolvedHomeUser[account.id] != nil {
                        setPlexTokenOverride(nil, for: account.id)
                        plexResolvedHomeUser[account.id] = nil
                        accountsProviders.registry.invalidate(accountID: account.id)
                        bumpIdentityGeneration(for: account.id, site: "ensure.staleOverride")
                    }
                    if pinTarget == nil {
                        pinTarget = (account.id, binding)
                    }
                } else {
                    // Unprotected Home user. If we're already resolved to exactly
                    // this user's complete identity, no refresh is needed.
                    if plexTokenOverrides[account.id] != nil,
                       plexResolvedHomeUser[account.id] == binding.homeUserID,
                       discoverToken(for: account.id) != nil {
                        continue
                    }
                    // Seed the cached token synchronously so the signed-in subtree
                    // paints immediately with the correct identity. On a cache hit
                    // this is the whole switch — no network on the launch path, and
                    // the background refresh below confirms the token (usually
                    // unchanged → no reload). On a cache miss (first launch for this
                    // Home user) Home paints fast with the admin token and reloads
                    // once when the switch lands; that token is then cached so it
                    // never happens again.
                    if let cached = plexHomeUserTokenCache.token(account: account.id, homeUser: binding.homeUserID) {
                        let identityChanged = plexTokenOverrides[account.id] != cached
                            || plexResolvedHomeUser[account.id] != binding.homeUserID
                        setPlexTokenOverride(cached, for: account.id)
                        plexResolvedHomeUser[account.id] = binding.homeUserID
                        plexCredentialSources[account.id] = CredentialSource(account)
                        // Restore the Discover credential in the same breath, or
                        // the watchlist is left without one on every warm start.
                        //
                        // Cleared FIRST when the identity changed, unconditionally.
                        // A cache entry can hold the server token without the
                        // Discover half — it predates that half being cached, or
                        // the app died between the two writes — and simply not
                        // overwriting left the PREVIOUS user's Discover token
                        // live under the new user's server token. The watchlist
                        // then found a credential, passed the fail-closed check,
                        // and read the wrong person's list. No credential is the
                        // correct state here: that path refuses to act.
                        if identityChanged {
                            plexDiscoverTokens.setToken(nil, for: account.id)
                        }
                        if let cachedDiscover = plexHomeUserTokenCache.discoverToken(
                            account: account.id,
                            homeUser: binding.homeUserID
                        ) {
                            plexDiscoverTokens.setToken(cachedDiscover, for: account.id)
                        }
                        accountsProviders.registry.invalidate(accountID: account.id)
                        if identityChanged {
                            bumpIdentityGeneration(for: account.id, site: "ensure.cachedOverride")
                        }
                        PlozzLog.boot("ensure.cachedOverride acct=\(account.id) home=\(binding.homeUserID) — instant paint")
                    } else {
                        // Cache miss on a DIFFERENT user than the one currently
                        // installed. Drop the old credentials now rather than
                        // leaving them live for the length of the network switch:
                        // the profile already reads as bound to the new user, so
                        // a watchlist import in that window sees a binding, finds
                        // the PREVIOUS user's Discover token, passes the
                        // fail-closed check, and imports the wrong person's list.
                        // Better to hold no credential — that path correctly
                        // refuses to act — than to hold the wrong one.
                        if plexTokenOverrides[account.id] != nil || plexResolvedHomeUser[account.id] != nil,
                           plexResolvedHomeUser[account.id] != binding.homeUserID {
                            setPlexTokenOverride(nil, for: account.id)
                            plexResolvedHomeUser[account.id] = nil
                            accountsProviders.registry.invalidate(accountID: account.id)
                            bumpIdentityGeneration(for: account.id, site: "ensure.missStaleOverride")
                        }
                        PlozzLog.boot("ensure.unprotectedSwitch acct=\(account.id) home=\(binding.homeUserID) — cache miss, async")
                    }
                    // Refresh in the background to keep the cached token fresh.
                    // `performPlexSwitch` only bumps the identity generation when the
                    // resolved token actually changed, so a warm-cache refresh that
                    // returns the same token triggers no reload. Capture the identity
                    // generation at spawn and pass it as `expectedGeneration` so a
                    // stale refresh — one whose profile was switched out from under it
                    // during the network window — drops its confirming write instead
                    // of re-installing the OLD Home-user's token under the NEW profile.
                    // Per-ACCOUNT, not the global counter: two valid cache-miss
                    // switches on different accounts capture the same global
                    // generation, and whichever lands first bumps it — rejecting
                    // the other as "stale" though its own binding is still
                    // current, leaving that account stuck on the owner token.
                    // Supersession is an account-level question.
                    let refreshGeneration = plexAccountIdentityGenerations[account.id, default: 0]
                    let activation = profileActivationGeneration
                    Task {
                        await performPlexSwitch(
                            accountID: account.id, homeUserID: binding.homeUserID,
                            pin: nil, expectedGeneration: refreshGeneration,
                            expectedActivation: activation
                        )
                    }
                }
            } else {
                if plexTokenOverrides[account.id] != nil || plexResolvedHomeUser[account.id] != nil {
                    setPlexTokenOverride(nil, for: account.id)
                    plexResolvedHomeUser[account.id] = nil
                    accountsProviders.registry.invalidate(accountID: account.id)
                    bumpIdentityGeneration(for: account.id, site: "ensure.dropOverride")
                }
            }
        }

        if let pin = pinTarget {
            let request = Self.pinRequest(profileID: profile.id, target: pin)
            if pendingPlexPINRequest != request {
                pendingPlexPINRequest = request
                plexPINEntryAvailability = .checking
                plexPINError = nil
            }
            checkPlexPINRequirement(for: request, suppliedPIN: prefilledPIN)
        } else {
            cancelPINRequirementCheck()
            pendingPlexPINRequest = nil
            plexPINEntryAvailability = .checking
            plexPINError = nil
        }
    }

    private func cancelPINRequirementCheck() {
        pinRequirementCheck?.task.cancel()
        pinRequirementCheck = nil
        isSubmittingPlexPIN = false
    }

    public func retryPlexPINRequirement() {
        guard let request = pendingPlexPINRequest else { return }
        cancelPINRequirementCheck()
        plexPINError = nil
        checkPlexPINRequirement(for: request, suppliedPIN: nil)
    }

    private func checkPlexPINRequirement(for request: PlexPINRequest, suppliedPIN: String?) {
        let profile = profilesModel.activeProfile
        let change = pendingBindingChange
        guard pendingPlexPINRequest == request,
              change == nil || (change?.request == request && change.map(isCurrentBindingChange) == true),
              let binding = change?.binding ?? profile.homeUserBinding(forPlexAccount: request.accountID),
              binding.homeUserID == request.homeUserID,
              let account = accountsProviders.accounts.first(where: { $0.id == request.accountID })
        else { return }
        let context = PINRequirementContext(
            request: request, profile: .init(profile), binding: binding,
            selectionID: change?.id,
            credentialSource: CredentialSource(account),
            activation: profileActivationGeneration,
            identityGeneration: plexAccountIdentityGenerations[account.id, default: 0]
        )
        guard suppliedPIN != nil || pinRequirementCheck?.context != context else { return }
        cancelPINRequirementCheck()
        isSubmittingPlexPIN = suppliedPIN != nil
        if suppliedPIN == nil { plexPINEntryAvailability = .checking }
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled { self.isSubmittingPlexPIN = false }
            }
            await self.refreshPlexPINRequirement(context, suppliedPIN: suppliedPIN)
        }
        pinRequirementCheck = (context, task)
    }

    func waitForPlexPINRequirementCheck() async {
        await pinRequirementCheck?.task.value
    }

    private func isCurrentPINRequirementCheck(_ context: PINRequirementContext, adminToken: String) -> Bool {
        !Task.isCancelled
            && pendingPlexPINRequest == context.request
            && profileActivationGeneration == context.activation
            && AutomaticSignInStore.Session.ProfileAccess(profilesModel.activeProfile) == context.profile
            && bindingMatches(context)
            && accountsProviders.accounts.first(where: { $0.id == context.request.accountID }).map(CredentialSource.init)
                == context.credentialSource
            && accountsProviders.accountStore.token(for: context.request.accountID) == adminToken
            && plexAccountIdentityGenerations[context.request.accountID, default: 0] == context.identityGeneration
    }

    private func bindingMatches(_ context: PINRequirementContext) -> Bool {
        if let selectionID = context.selectionID {
            guard let change = pendingBindingChange, change.id == selectionID else { return false }
            return isCurrentBindingChange(change) && change.binding == context.binding
        }
        return pendingBindingChange?.request.accountID != context.request.accountID
            && profilesModel.activeProfile.homeUserBinding(forPlexAccount: context.request.accountID) == context.binding
    }

    private func refreshPlexPINRequirement(_ context: PINRequirementContext, suppliedPIN: String?) async {
        let request = context.request
        guard let adminToken = accountsProviders.accountStore.token(for: request.accountID) else {
            PlozzLog.auth.error("Plex PIN status refresh has no account credential acct=\(request.accountID)")
            if pendingPlexPINRequest == request {
                plexPINError = ProfileLockCopy.plexSwitchFailed
                plexPINEntryAvailability = .unavailable
            }
            return
        }
        guard isCurrentPINRequirementCheck(context, adminToken: adminToken) else { return }
        if let suppliedPIN, !suppliedPIN.isEmpty {
            // Metadata must never veto, replace, or discard an entered PIN.
            let result = await performPlexSwitch(
                accountID: request.accountID, homeUserID: request.homeUserID, pin: suppliedPIN,
                expectedGeneration: context.identityGeneration, expectedActivation: context.activation,
                selectionID: context.selectionID
            )
            guard case let .failure(error) = result,
                  isCurrentPINRequirementCheck(context, adminToken: adminToken) else { return }
            guard error as? AppError == .unauthorized else {
                if plexPINEntryAvailability != .available {
                    plexPINEntryAvailability = .unavailable
                }
                return
            }
        }
        do {
            let users = try await plexHomeUsersFetch(adminToken, accountsProviders.deviceID)
            guard isCurrentPINRequirementCheck(context, adminToken: adminToken) else { return }
            guard let user = users.first(where: { $0.id == request.homeUserID }),
                  user.pinRequirementVerified == true else {
                PlozzLog.auth.error("Plex PIN status refresh missing selected user's protection metadata acct=\(request.accountID)")
                if plexPINError == nil { plexPINError = ProfileLockCopy.plexSwitchFailed }
                plexPINEntryAvailability = .unavailable
                return
            }
            guard !user.requiresPIN else {
                if context.selectionID == nil,
                   context.binding.requiresPIN != true || context.binding.pinRequirementVerified != true {
                    var binding = context.binding
                    binding.requiresPIN = true
                    binding.pinRequirementVerified = true
                    profilesModel.update(profilesModel.activeProfile.settingHomeUserBinding(
                        binding, forPlexAccount: request.accountID
                    ))
                }
                plexPINEntryAvailability = .available
                return
            }
            plexPINEntryAvailability = .checking
            plexPINError = nil
            // A token-only response may succeed using the owner's credential even
            // while a PIN is enabled. Require explicit metadata AND authentication.
            let result = await performPlexSwitch(
                accountID: request.accountID, homeUserID: request.homeUserID, pin: nil,
                expectedGeneration: context.identityGeneration, expectedActivation: context.activation,
                confirmedUnprotectedUser: user, selectionID: context.selectionID
            )
            if case .failure = result,
               isCurrentPINRequirementCheck(context, adminToken: adminToken) {
                plexPINEntryAvailability = .unavailable
                if plexPINError == nil { plexPINError = ProfileLockCopy.plexSwitchFailed }
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentPINRequirementCheck(context, adminToken: adminToken) else { return }
            PlozzLog.auth.error("Plex PIN status refresh failed acct=\(request.accountID): \(error)")
            if plexPINError == nil { plexPINError = ProfileLockCopy.plexSwitchFailed }
            plexPINEntryAvailability = .unavailable
        }
    }

    /// Builds the PIN prompt for a protected Home-user binding.
    private static func pinRequest(
        profileID: String,
        target: (accountID: String, binding: PlexHomeUserBinding)
    ) -> PlexPINRequest {
        PlexPINRequest(
            id: "\(profileID)#\(target.accountID)",
            accountID: target.accountID,
            homeUserID: target.binding.homeUserID,
            homeUserName: target.binding.name.isEmpty ? "Plex User" : target.binding.name,
            homeUserAvatarURL: target.binding.avatarURL
        )
    }

    /// Hands this model the PIN the user just entered to unlock a Plozz profile,
    /// for the case where they set that profile's lock to "same PIN as Plex".
    ///
    /// Read and dropped by the very next `ensurePlexIdentityForActiveProfile()`
    /// pass — which consumes it up front whether or not it ends up being used —
    /// so the plaintext can't linger in memory or be replayed against a later
    /// binding. Purely an optimisation of the *prompt*: the profile is already
    /// unlocked by the time this is called, so if Plex rejects it the person
    /// simply gets the Plex PIN screen they'd have got anyway.
    public func prefillPlexPIN(_ pin: String, forProfile profileID: String) {
        prefilledPlexPIN = (profileID: profileID, pin: pin)
    }

    /// Verifies that `pin` opens every PIN-protected Plex Home user bound to the
    /// profile, without publishing any token or changing the active identity.
    ///
    /// Used while creating a Profile Lock so "same as Plex" is a verified fact,
    /// not an unchecked promise discovered to be wrong at the next login.
    public func validatePlexPIN(
        _ pin: String,
        forProfile profileID: String
    ) async -> PlexPINValidationResult {
        guard let profile = profilesModel.profiles.first(where: { $0.id == profileID })
        else { return .unavailable }

        let targets = accountsProviders.accounts.compactMap { account
            -> (accountID: String, homeUserID: String)? in
            guard account.server.provider == .plex,
                  let binding = profile.homeUserBinding(
                      forPlexAccount: account.id
                  ),
                  binding.requiresPIN == true
            else { return nil }
            return (account.id, binding.homeUserID)
        }
        guard !targets.isEmpty else { return .unavailable }

        for target in targets {
            guard let adminToken = accountsProviders.accountStore.token(
                for: target.accountID
            ) else { return .unavailable }
            do {
                _ = try await plexHomeUserSwitch(
                    target.homeUserID,
                    pin,
                    adminToken,
                    accountsProviders.deviceID
                )
            } catch AppError.unauthorized {
                return .invalid
            } catch {
                return .unavailable
            }
        }
        return .valid
    }

    /// Takes the stashed PIN if it belongs to `profileID`, clearing it either way
    /// — including when it belonged to a different profile, since a stash that
    /// didn't match is stale by definition.
    private func consumePrefilledPIN(forProfile profileID: String) -> String? {
        defer { prefilledPlexPIN = nil }
        guard let stash = prefilledPlexPIN, stash.profileID == profileID else { return nil }
        return stash.pin
    }

    /// The account-level plex.tv token to use for Discover (watchlist) calls on
    /// `accountID`, or `nil` to use the account's stored token.
    public func discoverToken(for accountID: String) -> String? {
        guard hasCurrentCredentialSource(for: accountID) else { return nil }
        return plexDiscoverTokens.token(for: accountID)
    }

    /// Repairs an unprotected Home user's missing cloud credential through the
    /// same authenticated switch as startup, without refreshing the library
    /// session or using an owner credential for cloud requests.
    public func resolveDiscoverToken(for accountID: String) async throws -> String? {
        try Task.checkCancellation()
        guard hasCurrentCredentialSource(for: accountID) else {
            PlozzLog.auth.info("Plex cloud recovery requires reconciliation of replaced account credentials")
            throw AppError.unauthorized
        }
        guard accountsProviders.activeAccountIDs.contains(accountID),
              let account = accountsProviders.accounts.first(where: {
                  $0.id == accountID && $0.server.provider == .plex
              }) else {
            PlozzLog.auth.error("Plex cloud credential requested without an active Plex account")
            throw AppError.unauthorized
        }
        let profile = profilesModel.activeProfile
        guard let binding = profile.homeUserBinding(forPlexAccount: accountID) else { return nil }
        if let token = discoverToken(for: accountID) { return token }
        guard binding.requiresPIN == false, binding.pinRequirementVerified == true else {
            PlozzLog.auth.info("Missing protected Plex Home cloud credential requires the normal PIN flow")
            HandoffDiagnostics.emit("plex-home CLOUD_RECOVERY rejected=requires-pin")
            throw AppError.unauthorized
        }
        let activation = profileActivationGeneration
        let generation = plexAccountIdentityGenerations[accountID, default: 0]
        HandoffDiagnostics.emit("plex-home CLOUD_RECOVERY started")
        let result = await performPlexSwitch(
            accountID: accountID, homeUserID: binding.homeUserID, pin: nil,
            expectedGeneration: generation, expectedActivation: activation,
            refreshServerCredential: false
        )
        let token = try result.get()
        try Task.checkCancellation()
        guard activation == profileActivationGeneration,
              profile.id == profilesModel.activeProfileID,
              binding == profilesModel.activeProfile.homeUserBinding(forPlexAccount: accountID),
              accountsProviders.activeAccountIDs.contains(accountID),
              accountsProviders.accounts.first(where: { $0.id == accountID })?.credentialRevision
                == account.credentialRevision,
              discoverToken(for: accountID) == token else {
            throw CancellationError()
        }
        return token
    }

    /// Drops all Plex token overrides, falling back to stored (admin) tokens.
    private func clearPlexOverrides() {
        cancelPINRequirementCheck()
        pendingBindingChange = nil
        pendingPlexPINRequest = nil
        plexPINEntryAvailability = .checking
        plexPINError = nil
        let accountIDs = Set(plexTokenOverrides.keys).union(plexResolvedHomeUser.keys)
        plexTokenOverrides.removeAll()
        plexDiscoverTokens.removeAll()
        plexOverrideCredentialRevisions.removeAll()
        plexResolvedHomeUser.removeAll()
        plexPINVerifiedHomeUser.removeAll()
        plexCredentialSources.removeAll()
        if !accountIDs.isEmpty {
            for accountID in accountIDs {
                accountsProviders.registry.invalidate(accountID: accountID)
                plexAccountIdentityGenerations[accountID, default: 0] += 1
            }
            plexIdentityGeneration += 1
            PlozzLog.boot("genBump=\(self.plexIdentityGeneration) site=clearPlexOverrides")
        }
    }

    /// Authenticates the Home user and optionally refreshes the server credential.
    /// Only a changed server credential advances the library identity generation.
    @discardableResult
    private func performPlexSwitch(
        accountID: String, homeUserID: String, pin: String?,
        expectedGeneration: Int? = nil, expectedActivation: Int,
        refreshServerCredential: Bool = true,
        confirmedUnprotectedUser: PlexHomeUser? = nil,
        selectionID: UUID? = nil
    ) async -> Result<String, Error> {
        guard expectedActivation == profileActivationGeneration else {
            return .failure(CancellationError())
        }
        let activationGeneration = profileActivationGeneration
        let profile = profilesModel.activeProfile
        let profileAccess = AutomaticSignInStore.Session.ProfileAccess(profile)
        let change = selectionID.flatMap { id in pendingBindingChange.flatMap { $0.id == id ? $0 : nil } }
        guard selectionID == nil || change.map(isCurrentBindingChange) == true,
              pendingBindingChange?.request.accountID != accountID || change != nil else {
            return .failure(CancellationError())
        }
        let savedBinding = profile.homeUserBinding(forPlexAccount: accountID)
        let checksWithoutPIN = confirmedUnprotectedUser?.id == homeUserID
            && confirmedUnprotectedUser?.requiresPIN == false
            && confirmedUnprotectedUser?.pinRequirementVerified == true && pin == nil
        guard let account = accountsProviders.accounts.first(where: { $0.id == accountID }),
              let binding = change?.binding ?? savedBinding,
              binding.homeUserID == homeUserID,
              (binding.requiresPIN == false && binding.pinRequirementVerified == true)
                || pin?.isEmpty == false || checksWithoutPIN else {
            return .failure(CancellationError())
        }
        PlozzLog.auth.debug("performPlexSwitch acct=\(accountID) home=\(homeUserID) pin?=\(pin != nil)")
        guard let adminToken = accountsProviders.accountStore.token(for: accountID) else {
            // Surface a user-visible error instead of silently returning; otherwise a
            // PIN submission with no cached admin token vanishes (no dismissal, no error)
            // and the user can't tell whether the PIN was accepted.
            PlozzLog.auth.error("no admin token cached for acct=\(accountID) — surfacing error")
            if pin != nil { plexPINError = "Couldn’t reach this Plex account. Try signing in again." }
            return .failure(AppError.unauthorized)
        }
        func isCurrentSwitch() -> Bool {
            !Task.isCancelled
                && activationGeneration == profileActivationGeneration
                && profileAccess == .init(profilesModel.activeProfile)
                && profilesModel.activeProfile.homeUserBinding(forPlexAccount: accountID) == savedBinding
                && (change.map(isCurrentBindingChange) ?? (pendingBindingChange?.request.accountID != accountID))
                && accountsProviders.accounts.first(where: { $0.id == accountID }).map(CredentialSource.init)
                    == CredentialSource(account)
                && accountsProviders.accountStore.token(for: accountID) == adminToken
                && (expectedGeneration == nil || expectedGeneration == plexAccountIdentityGenerations[accountID, default: 0])
        }
        do {
            try Task.checkCancellation()
            let token = try await plexHomeUserSwitch(homeUserID, pin, adminToken, accountsProviders.deviceID)
            try Task.checkCancellation()
            guard !token.isEmpty else { throw AppError.unauthorized }
            PlozzLog.auth.debug("Plex Home-user switch authenticated")
            // `token` is the Home user's account-level plex.tv token. Re-resolve
            // it to THIS server's access token (the kind PMS authorizes browsing
            // with), mirroring how the owner account was built at sign-in. Falls
            // back to the account token if the per-server lookup fails so the
            // switch never silently dead-ends. See `plexServerTokenResolve`.
            var resolvedToken = token
            var gotServerToken = false
            if refreshServerCredential,
               let serverToken = await plexServerTokenResolve(account.server.id, token, accountsProviders.deviceID) {
                resolvedToken = serverToken
                gotServerToken = true
            }
            try Task.checkCancellation()
            guard isCurrentSwitch() else { return .failure(CancellationError()) }
            let currentSource = hasCurrentCredentialSource(for: accountID)
            let previousToken = currentSource ? plexTokenOverrides[accountID] : nil
            let changedUser = !currentSource || plexResolvedHomeUser[accountID] != homeUserID
            // Don't downgrade a good cached identity on a flaky refresh: if we
            // already have an override for this account and the per-server lookup
            // fell back to the account-level token, keep what we have instead of
            // replacing it (which would also force a needless reload).
            if refreshServerCredential, let previousToken, !gotServerToken,
               plexResolvedHomeUser[accountID] == homeUserID {
                PlozzLog.boot("refresh fell back to account token — keeping existing override acct=\(accountID)")
                resolvedToken = previousToken
            }
            if !refreshServerCredential,
               plexResolvedHomeUser[accountID] == homeUserID,
               let currentToken = discoverToken(for: accountID) {
                return .success(currentToken)
            }
            var liveBinding = binding
            if checksWithoutPIN {
                liveBinding.requiresPIN = false
                liveBinding.pinRequirementVerified = true
            } else if pin?.isEmpty == false {
                // Repair a legacy false flag without depending on a Home-user list.
                liveBinding.requiresPIN = true
                liveBinding.pinRequirementVerified = true
            }
            if refreshServerCredential {
                setPlexTokenOverride(resolvedToken, for: accountID)
                if changedUser, previousToken == resolvedToken {
                    plexOverrideCredentialRevisions[accountID] = CredentialRevision()
                }
            }
            // `token` IS the Home user's account-level plex.tv token — the one
            // Discover (the watchlist) needs, as opposed to the per-server token
            // installed above. Publish even when retaining a cached server token,
            // but only after all identity and credential guards have passed.
            plexDiscoverTokens.setToken(token, for: accountID)
            plexResolvedHomeUser[accountID] = homeUserID
            plexPINVerifiedHomeUser[accountID] = pin?.isEmpty == false ? homeUserID : nil
            plexCredentialSources[accountID] = CredentialSource(account)
            if liveBinding != savedBinding {
                profilesModel.update(profilesModel.activeProfile.settingHomeUserBinding(
                    liveBinding, forPlexAccount: accountID
                ))
            }
            if change != nil { pendingBindingChange = nil }
            HandoffDiagnostics.emit("plex-home SWITCH cloudReady=true serverRefresh=\(refreshServerCredential)")
            // The general cache is safe for manual switches only when unprotected.
            if liveBinding.requiresPIN == false && liveBinding.pinRequirementVerified == true {
                if refreshServerCredential {
                    plexHomeUserTokenCache.store(token: resolvedToken, account: accountID, homeUser: homeUserID)
                }
                // The Discover half of the same identity, so a warm start — which
                // restores the server token synchronously and skips this switch
                // entirely — can restore both. Without it the watchlist has no
                // credential and correctly refuses to act, reading as permanently
                // empty. Protected credentials only enter the opt-in startup store.
                plexHomeUserTokenCache.storeDiscoverToken(token, account: accountID, homeUser: homeUserID)
            }
            if refreshServerCredential {
                let completedPINRequest = pendingPlexPINRequest?.accountID == accountID
                    && pendingPlexPINRequest?.homeUserID == homeUserID
                if completedPINRequest {
                    pendingPlexPINRequest = nil
                    plexPINEntryAvailability = .checking
                    plexPINError = nil
                }
                // A cloud-only repair must leave the browsing tree and its
                // provider credential revision intact.
                if previousToken != resolvedToken || changedUser {
                    accountsProviders.registry.invalidate(accountID: accountID)
                    bumpIdentityGeneration(for: accountID, site: "performPlexSwitch")
                } else {
                    PlozzLog.boot("refresh unchanged — no genBump acct=\(accountID) home=\(homeUserID)")
                }
                // If another Plex account still needs a PIN, surface that next.
                if completedPINRequest { ensurePlexIdentityForActiveProfile() }
            }
            if refreshServerCredential || previousToken != nil {
                rememberAutomaticSignInIfReady()
            }
            return .success(token)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch AppError.unauthorized {
            guard isCurrentSwitch() else {
                return .failure(CancellationError())
            }
            PlozzLog.auth.info("Plex Home-user switch unauthorized")
            HandoffDiagnostics.emit("plex-home SWITCH failed=unauthorized")
            if refreshServerCredential, !checksWithoutPIN,
               pendingPlexPINRequest?.accountID == accountID {
                plexPINError = ProfileLockCopy.incorrectPIN
            }
            return .failure(AppError.unauthorized)
        } catch {
            guard isCurrentSwitch() else {
                return .failure(CancellationError())
            }
            PlozzLog.auth.error("Plex Home-user switch failed: \(error)")
            HandoffDiagnostics.emit("plex-home SWITCH failed=request")
            if refreshServerCredential, pendingPlexPINRequest?.accountID == accountID {
                plexPINError = ProfileLockCopy.plexSwitchFailed
            }
            return .failure(error)
        }
    }

    // MARK: Account lifecycle hooks (called by AppState's Events domain)

    /// Forgets an account's Plex Home-user identity — drops any token override,
    /// the resolved-user marker, and every cached token for it. Called when an
    /// account is removed or signed out.
    public func forgetAccount(_ id: String) {
        if pendingBindingChange?.request.accountID == id { discardPendingBindingChange() }
        if pinRequirementCheck?.context.request.accountID == id { cancelPINRequirementCheck() }
        invalidateAutomaticSignInSession()
        setPlexTokenOverride(nil, for: id)
        plexResolvedHomeUser[id] = nil
        plexCredentialSources[id] = nil
        plexHomeUserTokenCache.removeAll(account: id)
        // Invalidates any refresh still awaiting the network for this account.
        // Removal changes neither the profile's binding nor — without this — the
        // generation, so a switch that was already in flight would pass both
        // guards and re-install (and re-cache) credentials for an account the
        // user has just signed out of.
        bumpIdentityGeneration(for: id, site: "forgetAccount")
    }

    /// Wipes ALL Plex Home-user state (overrides, revisions, resolved-user map,
    /// the whole token cache, and any pending PIN / user-selection). Used by the
    /// debug "reset to first run" path once every account is gone.
    public func resetAllForDebug() {
        cancelPINRequirementCheck()
        pendingBindingChange = nil
        profileActivationGeneration += 1
        startupProfileAccess = nil
        authenticatedProfileAccess = nil
        setAutomaticallySignIn(false, profileIsUnlocked: false)
        plexTokenOverrides.removeAll()
        plexDiscoverTokens.removeAll()
        plexAccountIdentityGenerations.removeAll()
        plexOverrideCredentialRevisions.removeAll()
        plexResolvedHomeUser.removeAll()
        plexPINVerifiedHomeUser.removeAll()
        plexCredentialSources.removeAll()
        plexHomeUserTokenCache.removeAll()
        pendingPlexUserSelection = nil
        pendingPlexPINRequest = nil
        plexPINEntryAvailability = .checking
        plexPINError = nil
    }

    /// Presents (or clears) the "which Plex user are you?" onboarding selection.
    public func presentUserSelection(_ selection: PendingPlexUserSelection?) {
        pendingPlexUserSelection = selection
    }

    /// Clears the pending user selection once the onboarding step consumes it.
    public func clearUserSelection() {
        pendingPlexUserSelection = nil
    }
}
