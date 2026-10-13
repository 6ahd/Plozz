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
    func testSourcesStayAdmittedWhenBackgroundSyncSavesItsCheckpoint() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.show()
        try await waitUntil { fixture.state.runtime?.isCurrent == true }
        let runtime = try XCTUnwrap(fixture.state.runtime)
        var configuration = try fixture.store.load()
        configuration.syncCheckpoint = .init(profileID: fixture.profileID, accountEpoch: "sync-generation")
        try fixture.store.save(configuration)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(runtime.isCurrent, "No Retry or navigation should be needed after a sync checkpoint.")
        XCTAssertNil(runtime.catalog.issue)
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
        let window: UIWindow
        weak var previous: UIWindow?

        init() throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
            profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
            profileID = profiles.add(name: "Sources fixture").id
            profiles.select(profileID)
            accounts = AccountsProvidersModel(
                accountStore: AccountStore(secureStore: InMemorySecureStore()),
                registry: ProviderRegistry(), profilesModel: profiles
            )
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
            cache = LiveTVIndexedCache(
                url: directory.appendingPathComponent("catalog.sqlite"),
                namespace: profileID, authorizationScope: "iptv-profile-v1",
                secureStore: InMemorySecureStore()
            )
            store = LiveTVSourcesStore(secureStore: InMemorySecureStore(), namespace: profileID)
            let state = state
            let profiles = profiles
            runtime = LiveTVSourcesRuntime(
                profileID: profileID, store: store,
                approvals: LiveTVSourceApprovalStore(defaults: defaults, profileID: profileID, namespace: profileID),
                cache: cache, loader: EmptyLoader(),
                preferencesStore: LiveTVPreferencesStore(defaults: defaults, namespace: profileID),
                scanCoordinator: LiveTVChannelScanCoordinator(
                    store: LiveTVChannelHealthStore(defaults: defaults, namespace: profileID)
                ),
                context: {
                    state.authorized ? LiveTVSourceApprovalContext(profiles: profiles) : nil
                },
                accountAuthorizationID: { "fixture" }
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
