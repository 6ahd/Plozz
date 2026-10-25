import Foundation
import Observation
import CoreModels
import CoreNetworking

/// Connection phase for Nuvio. Like Last.fm, connecting carries the URL to show
/// as a QR: the user approves on nuvio.tv, nothing is typed on the TV.
public enum NuvioConnectionPhase: Equatable, Sendable {
    case unknown
    case unavailable
    case disconnected
    case connecting(loginURL: String, code: String)
    case connected(displayName: String)
    case error(LocalizedStringResource)
}

/// App-level façade for the Nuvio watch-progress sync.
@MainActor
@Observable
public final class NuvioService {
    public private(set) var phase: NuvioConnectionPhase
    /// The account's profiles once connected; more than one lets Settings offer
    /// a choice, since Nuvio keeps progress per profile.
    public private(set) var profiles: [NuvioProfile] = []
    public private(set) var selectedProfileIndex: Int?

    /// Stable scrobbler handle (only the token store's namespace changes).
    @ObservationIgnored public let scrobbler: any NuvioScrobbling

    @ObservationIgnored private let config: NuvioConfig
    @ObservationIgnored private let client: NuvioClient
    @ObservationIgnored private let session: NuvioSession
    @ObservationIgnored private let tokenStore: NuvioTokenStoring
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var profileGeneration: UInt64 = 0

    /// A TV login code lives about ten minutes; a fresh one is minted after.
    static let loginLifetime: TimeInterval = 600

    public init(config: NuvioConfig, http: HTTPClient = URLSessionHTTPClient(), tokenStore: NuvioTokenStoring) {
        self.config = config
        self.client = NuvioClient(config: config, http: http)
        self.session = NuvioSession(client: client, tokenStore: tokenStore)
        self.tokenStore = tokenStore
        if config.isConfigured {
            self.scrobbler = NuvioScrobbler(config: config, http: http, tokenStore: tokenStore)
            self.phase = .unknown
        } else {
            self.scrobbler = DisabledNuvioScrobbler()
            self.phase = .unavailable
        }
    }

    public var isConfigured: Bool { config.isConfigured }

    public func setActiveProfile(namespace: String?) async {
        profileGeneration &+= 1
        connectTask?.cancel()
        connectTask = nil
        tokenStore.setNamespace(namespace)
        profiles = []
        selectedProfileIndex = nil
        phase = config.isConfigured ? .unknown : .unavailable
        await refreshStatus()
    }

    public func refreshStatus() async {
        let generation = profileGeneration
        guard config.isConfigured else { phase = .unavailable; return }
        // A status check must not wipe the QR of a sign-in in progress.
        if case .connecting = phase { return }
        guard tokenStore.load() != nil else { phase = .disconnected; return }
        do {
            let tokens = try await session.validTokens()
            let list = try await client.profiles(accessToken: tokens.accessToken)
            guard generation == profileGeneration else { return }
            profiles = list
            let settled = try adoptProfile(in: list, tokens: tokens)
            selectedProfileIndex = settled.profileIndex
            phase = .connected(displayName: settled.displayName)
        } catch {
            guard generation == profileGeneration else { return }
            // Only the server rejecting the session signs out; a network blip
            // keeps the stored session and shows what was last known.
            if CredentialRejection.discardsStoredCredential(error) {
                try? tokenStore.clear()
                phase = .disconnected
            } else if let tokens = tokenStore.load() {
                selectedProfileIndex = tokens.profileIndex
                phase = .connected(displayName: tokens.displayName)
            } else {
                phase = .disconnected
            }
        }
    }

    /// Chooses which Nuvio profile Plozz writes progress to.
    public func selectProfile(_ profile: NuvioProfile) {
        guard var tokens = tokenStore.load() else { return }
        tokens.profileIndex = profile.index
        tokens.profileName = profile.name
        try? tokenStore.save(tokens)
        selectedProfileIndex = profile.index
        phase = .connected(displayName: tokens.displayName)
    }

    public func connect() {
        guard config.isConfigured else { phase = .unavailable; return }
        connectTask?.cancel()
        profileGeneration &+= 1
        let generation = profileGeneration
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let clientID = NuvioClientIdentity.current()
                while true {
                    try Task.checkCancellation()
                    let anon = try await self.client.anonymousSession(clientID: clientID)
                    let login = try await self.client.startTVLogin(
                        anonToken: anon, nonce: NuvioClientIdentity.nonce(), deviceName: Self.deviceName
                    )
                    guard generation == self.profileGeneration else { return }
                    self.phase = .connecting(loginURL: login.url, code: login.code)
                    guard try await self.awaitApproval(login) else { continue }
                    var tokens = try await self.client.exchangeTVLogin(login)
                    try Task.checkCancellation()
                    guard generation == self.profileGeneration else { return }
                    try? self.tokenStore.save(tokens)
                    let list = (try? await self.client.profiles(accessToken: tokens.accessToken)) ?? []
                    guard generation == self.profileGeneration else { return }
                    self.profiles = list
                    tokens = (try? self.adoptProfile(in: list, tokens: tokens)) ?? tokens
                    self.selectedProfileIndex = tokens.profileIndex
                    self.phase = .connected(displayName: tokens.displayName)
                    return
                }
            } catch is CancellationError {
                // Cancelled by user.
            } catch let error as AppError {
                if error == .cancelled { return }
                guard generation == self.profileGeneration else { return }
                self.phase = .error(error.userMessage)
            } catch {
                guard generation == self.profileGeneration else { return }
                self.phase = .error(AppError.unknown("").userMessage)
            }
        }
    }

    public func cancelConnect() {
        profileGeneration &+= 1
        connectTask?.cancel()
        connectTask = nil
        phase = config.isConfigured ? .disconnected : .unavailable
    }

    public func disconnect() async {
        profileGeneration &+= 1
        connectTask?.cancel()
        connectTask = nil
        try? tokenStore.clear()
        profiles = []
        selectedProfileIndex = nil
        phase = config.isConfigured ? .disconnected : .unavailable
    }

    // MARK: - Helpers

    private static var deviceName: String {
        #if os(tvOS)
        return "Plozz • Apple TV"
        #else
        return "Plozz • iPhone/iPad"
        #endif
    }

    /// Polls until approved (`true`) or the code expires (`false`, mint another).
    private func awaitApproval(_ login: NuvioTVLogin) async throws -> Bool {
        let deadline = Date().addingTimeInterval(Self.loginLifetime)
        while Date() < deadline {
            try Task.checkCancellation()
            switch try await client.pollTVLogin(login) {
            case .approved: return true
            case .expired: return false
            case .pending: break
            }
            try await Task.sleep(nanoseconds: UInt64(login.pollInterval * 1_000_000_000))
        }
        return false
    }

    /// Keeps the saved profile when it still exists, otherwise takes the first
    /// one, and stores the choice with the session.
    private func adoptProfile(in list: [NuvioProfile], tokens: NuvioTokens) throws -> NuvioTokens {
        var tokens = tokenStore.load() ?? tokens
        let chosen = list.first { $0.index == tokens.profileIndex } ?? list.first
        if let chosen, chosen.index != tokens.profileIndex || chosen.name != tokens.profileName {
            tokens.profileIndex = chosen.index
            tokens.profileName = chosen.name
            try tokenStore.save(tokens)
        }
        return tokens
    }
}

/// Factory for building `NuvioService`.
public enum NuvioServiceFactory {
    @MainActor
    public static func make(
        config: NuvioConfig = .resolved(),
        http: HTTPClient = URLSessionHTTPClient(),
        tokenStore: NuvioTokenStoring? = nil,
        namespace: String? = nil
    ) -> NuvioService {
        let store = tokenStore ?? defaultTokenStore()
        store.setNamespace(namespace)
        return NuvioService(config: config, http: http, tokenStore: store)
    }

    public static func defaultTokenStore() -> NuvioTokenStoring {
        #if canImport(Security)
        return KeychainNuvioTokenStore()
        #else
        return InMemoryNuvioTokenStore()
        #endif
    }
}
