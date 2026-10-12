import Foundation
import Observation

/// Persists `HomeLibraryVisibility` across launches.
public protocol HomeLibraryVisibilityStoring: Sendable {
    func load() -> HomeLibraryVisibility
    func save(_ visibility: HomeLibraryVisibility)
    func loadServerDefaults() -> CachedHomeRowDefaults?
    func saveServerDefaults(_ snapshot: CachedHomeRowDefaults)
}

public extension HomeLibraryVisibilityStoring {
    func loadServerDefaults() -> CachedHomeRowDefaults? { nil }
    func saveServerDefaults(_ snapshot: CachedHomeRowDefaults) {}
}

public final class HomeLibraryVisibilityStore: HomeLibraryVisibilityStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    /// - Parameter namespace: per-profile scope. `nil` (the default/primary
    ///   profile) uses the legacy un-suffixed key so upgrading installs keep
    ///   their Home customization; other profiles pass their `Profile.id` so each
    ///   profile gets its own independent set of hidden libraries.
    public init(defaults: UserDefaults = .standard, namespace: String? = nil) {
        self.defaults = defaults
        self.key = SettingsKey.scoped("com.plozz.homeLibraryVisibility", namespace: namespace)
    }

    public func load() -> HomeLibraryVisibility {
        guard let data = defaults.data(forKey: key),
              let visibility = try? JSONDecoder().decode(HomeLibraryVisibility.self, from: data) else {
            return .default
        }
        return visibility
    }

    public func save(_ visibility: HomeLibraryVisibility) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(visibility) {
            defaults.set(data, forKey: key)
        }
    }

    public func loadServerDefaults() -> CachedHomeRowDefaults? {
        guard let data = defaults.data(forKey: key + ".serverDefaults") else { return nil }
        return try? JSONDecoder().decode(CachedHomeRowDefaults.self, from: data)
    }

    public func saveServerDefaults(_ snapshot: CachedHomeRowDefaults) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key + ".serverDefaults")
        }
    }
}

/// Observable wrapper so the Settings checklist can two-way bind the per-library
/// toggles (enabled + show-on-home) and the merge switch, and have each choice
/// persisted immediately + broadcast to Home / Search / Music.
@MainActor
@Observable
public final class HomeLibraryVisibilityModel {
    public private(set) var visibility: HomeLibraryVisibility
    public private(set) var serverMatchError: AppError?

    private let store: HomeLibraryVisibilityStoring
    @ObservationIgnored private var cachedServerDefaults: CachedHomeRowDefaults?
    @ObservationIgnored private var lastServerCheck: Date?
    @ObservationIgnored private var serverRequestScope: [String] = []
    @ObservationIgnored private var serverRequest: Task<Result<ServerHomeLayout?, AppError>, Never>?

    public init(store: HomeLibraryVisibilityStoring = HomeLibraryVisibilityStore()) {
        self.store = store
        self.visibility = store.load()
        self.cachedServerDefaults = store.loadServerDefaults()
    }

    /// Called only by a real Home refresh or the open arranger, never a timer.
    public func prepareServerDefaults(accounts: [ResolvedAccount], now: Date = Date()) async {
        guard visibility.rowCustomization?.defaults == .matchServer else { return }
        let sources = accounts.sorted { $0.account.id < $1.account.id }
        let scope = sources.flatMap {
            [$0.account.id, $0.account.server.provider.rawValue,
             $0.account.server.identityKey, $0.provider.session.userID]
        }
        if scope == cachedServerDefaults?.scope,
           let lastServerCheck, now.timeIntervalSince(lastServerCheck) < 120 {
            visibility.rowCustomization?.resolvedDefaults = cachedServerDefaults?.defaults
            return
        }
        let servers = Set(sources.map {
            $0.account.server.provider.rawValue + ":" + $0.account.server.identityKey
        })
        let users = Set(sources.map(\.provider.session.userID))
        if servers.count > 1 || users.count > 1 {
            acceptServerDefaults(.init(mode: .combined), scope: scope, now: now)
            return
        }
        guard let source = sources.first else {
            acceptServerDefaults(.init(mode: .providerFallback), scope: scope, now: now)
            return
        }
        visibility.rowCustomization?.resolvedDefaults =
            cachedServerDefaults?.scope == scope ? cachedServerDefaults?.defaults : nil
        let request: Task<Result<ServerHomeLayout?, AppError>, Never>
        if serverRequestScope == scope, let pending = serverRequest {
            request = pending
        } else {
            serverRequest?.cancel()
            serverRequestScope = scope
            request = Task {
                do {
                    return .success(try await source.provider.serverHomeLayout())
                } catch is CancellationError {
                    return .failure(.cancelled)
                } catch {
                    return .failure((error as? AppError) ?? .unknown(""))
                }
            }
            serverRequest = request
        }
        let result = await request.value
        guard !Task.isCancelled, serverRequestScope == scope,
              visibility.rowCustomization?.defaults == .matchServer else { return }
        serverRequest = nil
        switch result {
        case let .success(layout?):
            let rows = layout.sections.map {
                HomeServerRowDefinition(
                    accountID: source.account.id, serverName: source.account.server.name,
                    providerKind: source.account.server.provider, section: $0
                )
            }
            acceptServerDefaults(.init(
                mode: .server, order: rows.map(\.id), serverRows: rows,
                omitsMusic: layout.omitsMusic, omitsReading: layout.omitsReading,
                source: layout.source
            ), scope: scope, now: now)
        case .success(nil):
            acceptServerDefaults(.init(mode: .providerFallback), scope: scope, now: now)
        case let .failure(error):
            if error != .cancelled { serverMatchError = error }
        }
    }

    private func acceptServerDefaults(
        _ defaults: HomeResolvedRowDefaults, scope: [String], now: Date
    ) {
        serverRequest?.cancel()
        serverRequest = nil
        serverRequestScope = scope
        serverMatchError = nil
        lastServerCheck = now
        let snapshot = CachedHomeRowDefaults(scope: scope, defaults: defaults)
        if cachedServerDefaults != snapshot { store.saveServerDefaults(snapshot) }
        cachedServerDefaults = snapshot
        visibility.rowCustomization?.resolvedDefaults = defaults
    }

    public func applyRows(
        _ sections: OrderedVisibilityList.Sections<HomeRowID>, choices: [HomeRowChoice]
    ) {
        visibility.applyRows(sections, choices: choices)
        store.save(visibility)
    }

    public func useRowDefaults(_ defaults: HomeRowCustomization.Defaults) {
        visibility.rowCustomization = HomeRowCustomization(defaults: defaults)
        serverMatchError = nil
        store.save(visibility)
    }

    // MARK: - Merge

    /// Whether Home merges every library into unified cross-server rows.
    public var mergeLibrariesOnHome: Bool {
        visibility.mergeLibrariesOnHome
    }

    /// Sets the all-or-nothing "merge libraries on Home" switch and persists.
    public func setMergeLibrariesOnHome(_ merge: Bool) {
        guard visibility.mergeLibrariesOnHome != merge else { return }
        visibility.mergeLibrariesOnHome = merge
        store.save(visibility)
    }

    // MARK: - Global Home rows

    /// Whether a global Home row (Continue Watching / Watchlist / Recently Added)
    /// is shown (default on).
    public func isGlobalRowEnabled(_ row: HomeGlobalRow) -> Bool {
        visibility.isGlobalRowEnabled(row)
    }

    /// Shows/hides a global Home row and persists.
    public func setGlobalRowEnabled(_ enabled: Bool, for row: HomeGlobalRow) {
        visibility.setGlobalRowEnabled(enabled, for: row)
        store.save(visibility)
    }

    /// Whether Continue Watching identifies cards by show artwork + logo (default
    /// on) rather than by the episode thumbnail.
    public var continueWatchingShowsSeriesArtwork: Bool {
        visibility.continueWatchingShowsSeriesArtwork
    }

    /// Sets the Continue Watching artwork treatment and persists.
    public func setContinueWatchingShowsSeriesArtwork(_ showsSeriesArtwork: Bool) {
        guard visibility.continueWatchingShowsSeriesArtwork != showsSeriesArtwork else { return }
        visibility.continueWatchingShowsSeriesArtwork = showsSeriesArtwork
        store.save(visibility)
    }

    // MARK: - Per-library Home rows (unmerged, opt-in)

    /// Whether a per-library row is opted in to Home (default off).
    public func isLibraryRowEnabled(_ libraryKey: String, kind: LibraryHomeRowKind) -> Bool {
        visibility.isLibraryRowEnabled(libraryKey, kind: kind)
    }

    /// Opts a per-library row in/out of Home and persists.
    public func setLibraryRowEnabled(_ enabled: Bool, libraryKey: String, kind: LibraryHomeRowKind) {
        visibility.setLibraryRowEnabled(enabled, libraryKey: libraryKey, kind: kind)
        store.save(visibility)
    }

    /// Seeds all provided per-library rows **on** the first time the user
    /// unmerges, then persists. Called when the merge switch is turned **off** so
    /// the unmerged Home starts populated rather than empty (see
    /// ``HomeLibraryVisibility/seedLibraryRowsIfNeeded(_:)``). A no-op once the
    /// one-time seeding has run, so it never re-seeds over the user's row choices.
    public func seedLibraryRowsIfNeeded(_ rows: [(libraryKey: String, kind: LibraryHomeRowKind)]) {
        if visibility.seedLibraryRowsIfNeeded(rows) {
            store.save(visibility)
        }
    }

    // MARK: - Per-library predicates

    /// Whether the library is on (not disabled).
    public func isEnabled(_ key: String) -> Bool {
        visibility.isEnabled(key)
    }

    /// Whether the library appears on Home (now just ``isEnabled(_:)`` — the
    /// separate Home-only opt-out was retired).
    public func isVisibleOnHome(_ key: String) -> Bool {
        visibility.isVisibleOnHome(key)
    }

    /// Compatibility alias for ``isVisibleOnHome(_:)``.
    public func isVisible(_ key: String) -> Bool {
        visibility.isVisible(key)
    }

    // MARK: - Per-library mutation

    /// Turns a library on/off and persists immediately.
    public func setEnabled(_ enabled: Bool, for key: String) {
        visibility.setEnabled(enabled, for: key)
        store.save(visibility)
    }
}
