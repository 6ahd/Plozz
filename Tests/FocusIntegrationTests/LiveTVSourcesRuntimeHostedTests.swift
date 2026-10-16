@testable import AppRuntime
import CoreModels
import CoreSecureStore
import FeatureAuthCore
import FeatureLiveTV
import FeatureLiveTVCore
import Observation
import SwiftUI
import UIKit
import XCTest

@MainActor
final class LiveTVSourcesRuntimeHostedTests: XCTestCase {
    func testSyncedIdentityMarkerDoesNotHideLoadedIPTVSources() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        fixture.profiles.noteIdentityQuestions(
            for: ["iptv"], forProfile: fixture.profileID, knownNonPlexAccountIDs: []
        )

        try await waitUntil {
            fixture.runtime.isCurrent && fixture.runtime.catalog.catalog.channels.count == 1
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fixture.profiles.activeProfile.pendingIdentityAccountIDs, ["iptv"])
        XCTAssertFalse(fixture.accounts.activeProfileAwaitsIdentity)
        XCTAssertTrue(fixture.runtime.isCurrent)
        XCTAssertEqual(fixture.runtime.catalog.catalog.channels.count, 1)
        XCTAssertNil(fixture.runtime.catalog.issue)
    }

    func testSourceUpdateDuringIPTVRestoreDoesNotLeaveProfileAccessFailure() async throws {
        let fixture = try Fixture(hasIPTV: true, pausesCatalog: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.provider.isWaiting }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        let identity = runtime.authorityID
        var configuration = try runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try runtime.store.save(configuration)
        fixture.provider.release()

        try await waitUntil {
            runtime.isCurrent && runtime.catalog.catalog.channels.map(\.name) == ["IPTV channel"]
        }
        XCTAssertEqual(runtime.authorityID, identity, "Neither profile nor account access changed.")
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(runtime.catalog.imports.configuration.servers, configuration.servers)
        XCTAssertEqual(try runtime.store.load().servers, configuration.servers)
    }

    func testLoadedIPTVTracksSourceChangesWithoutReopeningSources() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        let runtime = fixture.runtime
        let identity = runtime.authorityID
        var configuration = try runtime.store.load()
        configuration.servers[0].isEnabled = false
        try runtime.store.save(configuration)
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.isEmpty }

        configuration.servers[0].isEnabled = true
        try runtime.store.save(configuration)
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.count == 1 }
        configuration.servers[0].name = "Synced IPTV"
        try fixture.store.save(configuration)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidApply, object: fixture.profileID)
        try await waitUntil {
            runtime.isCurrent && runtime.catalog.imports.configuration.servers == configuration.servers
        }
        XCTAssertEqual(runtime.authorityID, identity)
        XCTAssertEqual(runtime.catalog.catalog.channels.count, 1)
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(try runtime.store.load().servers, configuration.servers)
    }

    func testSourcesStayAdmittedWhenBackgroundSyncSavesItsCheckpoint() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        try await waitUntil { runtime.catalog.catalog.channels.count == 1 }
        let reads = fixture.provider.catalogReads
        var configuration = try fixture.store.load()
        configuration.syncCheckpoint = .init(profileID: fixture.profileID, accountEpoch: "sync-generation")
        try fixture.store.save(configuration)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidChange, object: fixture.profileID)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidApply, object: fixture.profileID)
        NotificationCenter.default.post(name: .plozzLiveTVPortableStateDidChange, object: "another-profile")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(runtime.isCurrent, "No Retry or navigation should be needed after a sync checkpoint.")
        XCTAssertNil(runtime.catalog.issue)
        XCTAssertEqual(runtime.catalog.catalog.channels.count, 1)
        XCTAssertEqual(fixture.provider.catalogReads, reads, "Bookkeeping must not restart the catalogue.")
    }

    func testSourceUpdatesCannotReadmitLockedProfileOrPublishLateChannels() async throws {
        let fixture = try Fixture(hasIPTV: true, pausesCatalog: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.provider.isWaiting }
        let runtime = fixture.runtime
        fixture.state.authorized = false
        var configuration = try runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try runtime.store.save(configuration)
        fixture.provider.release()
        try await waitUntil { runtime.authorityID == nil && runtime.catalog.issue == .authorization }
        XCTAssertFalse(runtime.isCurrent)
        XCTAssertTrue(runtime.catalog.catalog.channels.isEmpty)

        fixture.state.authorized = true
        try await waitUntil { runtime.isCurrent && runtime.catalog.catalog.channels.count == 1 }
        XCTAssertNil(runtime.catalog.issue)
    }

    func testBackgroundSourceUpdateWaitsForPresentationToResume() async throws {
        let fixture = try Fixture(hasIPTV: true)
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.runtime.catalog.catalog.channels.count == 1 }
        fixture.state.phase = .background
        try await waitUntil { !fixture.runtime.isCurrent }
        let reads = fixture.provider.catalogReads
        var configuration = try fixture.runtime.store.load()
        configuration.servers[0].name = "Updated IPTV"
        try fixture.runtime.store.save(configuration)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(fixture.runtime.catalog.catalog.channels.isEmpty)
        XCTAssertEqual(fixture.provider.catalogReads, reads)

        fixture.state.phase = .active
        try await waitUntil { fixture.runtime.isCurrent && fixture.runtime.catalog.catalog.channels.count == 1 }
        XCTAssertEqual(fixture.runtime.catalog.imports.configuration.servers, configuration.servers)
        XCTAssertNil(fixture.runtime.catalog.issue)
    }

    func testSourcesStayAdmittedWhileOpeningAndClosingAnEditor() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        fixture.state.path = [1]
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(runtime.isCurrent)
        fixture.state.path = []
        try await waitUntil { runtime.isCurrent }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(runtime.isCurrent)
        XCTAssertNil(runtime.catalog.issue)
    }

    func testSourcesReadmitAutomaticallyAfterPresentationAndAuthorityChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        for index in 0..<3 {
            fixture.state.presented = false
            try await waitUntil { !runtime.isCurrent }
            fixture.state.presented = true
            try await waitUntil { runtime.isCurrent }
            fixture.profiles.setActiveAccountIDs(["generation-\(index)"], for: fixture.profileID)
            try await waitUntil { runtime.isCurrent }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(runtime.isCurrent)
            XCTAssertNil(runtime.catalog.issue)
            XCTAssertTrue(runtime === fixture.state.runtime)
        }
        fixture.state.phase = .inactive
        try await waitUntil { !runtime.isCurrent }
        fixture.state.phase = .active
        try await waitUntil { runtime.isCurrent }
        XCTAssertNil(runtime.catalog.issue)
    }

    func testSourcesRecoverAutomaticallyAfterProfileAuthorizationReturns() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.state.authorized = false
        fixture.show()
        try await waitUntil { fixture.state.runtime?.catalog.issue == .authorization }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        fixture.state.authorized = true
        try await waitUntil { runtime.isCurrent }
        XCTAssertNil(runtime.catalog.issue)
        fixture.state.authorized = false
        try await waitUntil { !runtime.isCurrent }
        XCTAssertTrue(runtime.catalog.catalog.channels.isEmpty)
    }

    private func waitUntil(
        file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Sources must settle without pressing Retry or reopening.", file: file, line: line)
    }

    @MainActor @Observable
    final class State {
        var presented = true
        var authorized = true
        var phase: ScenePhase = .active
        var path: [Int] = []
        @ObservationIgnored var runtime: LiveTVSourcesRuntime?
    }

    private struct Page: View {
        let state: State
        let profiles: ProfilesModel
        let accounts: AccountsProvidersModel
        let cache: LiveTVIndexedCache
        let profileID: String
        let runtime: LiveTVSourcesRuntime

        var body: some View {
            NavigationStack(path: Binding(get: { state.path }, set: { state.path = $0 })) {
                LiveTVSourcesRuntimeHost(
                    profileID: profileID, namespace: profileID,
                    profiles: profiles, accounts: accounts, cache: cache,
                    isPresented: state.presented,
                    isProfileAuthorized: { state.authorized },
                    content: capture, runtime: runtime
                )
                .navigationDestination(for: Int.self) { _ in Text("Source editor") }
            }
            .environment(profiles)
            .environment(\.scenePhase, state.phase)
        }

        private func capture(_ runtime: LiveTVSourcesRuntime) -> some View {
            state.runtime = runtime
            return LiveTVSourcesView(store: runtime.store, catalog: runtime.catalog)
        }
    }

    @MainActor private final class Fixture {
        let domain = "LiveTVSourcesRuntimeHostedTests." + UUID().uuidString
        let defaults: UserDefaults
        let profiles: ProfilesModel
        let accounts: AccountsProvidersModel
        let profileID: String
        let directory: URL
        let cache: LiveTVIndexedCache
        let state = State()
        let runtime: LiveTVSourcesRuntime
        let store: LiveTVSourcesStore
        let provider: CachedIPTVProvider
        let window: UIWindow
        weak var previous: UIWindow?

        init(hasIPTV: Bool = false, pausesCatalog: Bool = false) throws {
            provider = CachedIPTVProvider(paused: pausesCatalog)
            defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
            profileID = profiles.add(name: "Sources fixture").id
            profiles.select(profileID)
            let accountStore = AccountStore(secureStore: InMemorySecureStore())
            if hasIPTV {
                try accountStore.add(Account(
                    id: "iptv",
                    server: MediaServer(
                        id: "server", name: "IPTV",
                        baseURL: URL(string: "https://iptv.example")!, provider: .iptv
                    ),
                    userID: "viewer", userName: "Viewer", deviceID: "device"
                ), token: "fixture")
            }
            accounts = AccountsProvidersModel(
                accountStore: accountStore,
                registry: ProviderRegistry(), profilesModel: profiles
            )
            accounts.reloadAccounts()
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
            cache = LiveTVIndexedCache(
                url: directory.appendingPathComponent("catalog.sqlite"),
                namespace: profileID, authorizationScope: "iptv-profile-v1",
                secureStore: InMemorySecureStore()
            )
            store = LiveTVSourcesStore(secureStore: InMemorySecureStore(), namespace: profileID)
            if hasIPTV {
                try store.save(.init(servers: [
                    .init(id: "source", name: "IPTV", accountID: "iptv")
                ]))
            }
            let state = state
            let profiles = profiles
            let accounts = accounts
            let provider = provider
            let approvals = LiveTVSourceApprovalStore(
                defaults: defaults, profileID: profileID, namespace: profileID
            )
            runtime = LiveTVSourcesRuntime(
                profileID: profileID,
                store: LiveTVApprovalAwareSourcesStore(underlying: store, approvals: approvals),
                approvals: approvals,
                cache: cache, loader: EmptyLoader(),
                preferencesStore: LiveTVPreferencesStore(defaults: defaults, namespace: profileID),
                scanCoordinator: LiveTVChannelScanCoordinator(
                    store: LiveTVChannelHealthStore(defaults: defaults, namespace: profileID)
                ),
                context: {
                    state.authorized && !accounts.activeProfileAwaitsIdentity
                        ? LiveTVSourceApprovalContext(profiles: profiles) : nil
                },
                accountAuthorizationID: { accounts.liveTVAuthorizationID },
                serverProviderResolver: { id in
                    guard hasIPTV, id == "iptv" else { return nil }
                    return .init(accountID: id, authorizationID: "fixture", kind: .iptv, provider: provider)
                }
            )
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            previous = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            #if os(iOS)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            #else
            window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            #endif
        }

        func show() {
            window.rootViewController = UIHostingController(rootView: Page(
                state: state, profiles: profiles, accounts: accounts, cache: cache,
                profileID: profileID, runtime: runtime
            ))
            window.makeKeyAndVisible()
        }

        func close() {
            provider.release()
            runtime.invalidate()
            window.isHidden = true
            window.rootViewController = nil
            state.runtime = nil
            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: domain)
            if FileManager.default.fileExists(atPath: directory.path) {
                do { try FileManager.default.removeItem(at: directory) }
                catch { XCTFail("Could not remove this fixture's cache: \(error)") }
            }
        }
    }

    @MainActor private final class CachedIPTVProvider: ServerLiveTVProviding {
        private var paused: Bool
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var catalogReads = 0
        var isWaiting: Bool { !waiters.isEmpty }

        init(paused: Bool) { self.paused = paused }

        func release() {
            paused = false
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }

        func cachedLiveTVCatalog() async throws -> ServerLiveTVCatalogSnapshot? {
            catalogReads += 1
            if paused {
                await withCheckedContinuation { waiters.append($0) }
            }
            try Task.checkCancellation()
            return .init(channels: [.init(id: "channel", name: "IPTV channel")], supportsGuide: false)
        }

        func liveTVAvailability() async throws -> ServerLiveTVAvailability {
            XCTFail("Restoring Sources must use the existing IPTV catalogue.")
            throw AppError.serverUnreachable
        }

        func liveTVChannels() async throws -> [ServerLiveTVChannel] {
            XCTFail("Restoring Sources must not refresh channels.")
            return []
        }

        func liveTVGuide(channelIDs: [String], from: Date, to: Date) async throws -> [ServerLiveTVProgramme] {
            XCTFail("Restoring Sources must not refresh the guide.")
            return []
        }

        func openLiveTVChannel(id: String) async throws -> any LiveTVStreamLease {
            throw ServerLiveTVError.tunerUnavailable
        }
    }

    private struct EmptyLoader: LiveTVSourceLoading {
        func loadPlaylist(from url: URL) async throws -> LiveTVPlaylistImport {
            XCTFail("Presentation recovery must use the cache, not refetch playlists.")
            throw LiveTVSourceImportError.downloadFailed
        }

        func loadGuide(
            from url: URL, channels: [LiveTVPrototypeChannel], now: Date
        ) async throws -> LiveTVGuideImport {
            XCTFail("Presentation recovery must not refetch guides.")
            throw LiveTVSourceImportError.downloadFailed
        }
    }
}
