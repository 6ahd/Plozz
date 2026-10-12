import CoreModels
import CoreUI
#if os(tvOS)
@testable import FeatureHome
#elseif os(iOS)
@testable import AppShelliOS
#endif
import FeatureSettings
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class HomeRowArrangementHostedTests: XCTestCase {
    #if os(iOS)
    func testOfflineServerDoesNotAddAGlobalWarningToHomeCustomization() async throws {
        let suite = "HomeSettingsOffline.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let offline = HomeSettingsLibraryProvider(name: "Offline server", isOffline: true)
        let online = HomeSettingsLibraryProvider(name: "Available server", isOffline: false)
        visibility.applyRows(
            .init(enabled: [.global(.continueWatching)], disabled: [.global(.watchlist)]),
            choices: HomeRowChoice.shared
        )
        let saved = store.load()
        try await withWindow {
            NavigationStack {
                PlozziOSHomeSettingsView(
                    hero: HeroSettingsModel(store: InMemoryHeroSettingsStore()),
                    heroBackground: HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()),
                    visibility: visibility,
                    accounts: [offline, online].map {
                        ResolvedAccount(account: Account(from: $0.session), provider: $0)
                    }
                )
            }
        } inspect: { window in
            let deadline = ContinuousClock.now + .seconds(3)
            while await online.libraryRequests == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let offlineRequests = await offline.libraryRequests
            XCTAssertEqual(offlineRequests, 1)
            let lines = try await self.capture(window, name: "Home customization with an offline server")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Available server"), text)
            XCTAssertTrue(text.contains("Movies"), text)
            XCTAssertFalse(text.contains("Some libraries are"), text)
            XCTAssertFalse(text.contains("Retry"), text)
            XCTAssertEqual(store.load(), saved)
        }
    }
    #endif

    func testSharedArrangerReflectsCrossLibraryOrderAndPersistsEdits() async throws {
        let suite = "HomeRowArrangement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let libraries = ["Alpha", "Beta"].map {
            AggregatedLibrary(
                accountID: $0, accountName: "Viewer", serverName: "Server",
                providerKind: .mediaShare,
                library: MediaLibrary(id: $0, title: "\($0) Movies", kind: .movie)
            )
        }

        let choices = libraries.flatMap(HomeRowChoice.baseRows) + HomeRowChoice.shared
        let ids: [HomeRowID] = [
            .global(.continueWatching), .library(libraries[0].key, kind: .recentlyAdded),
            .global(.watchlist), .library(libraries[1].key, kind: .recentlyAdded)
        ]
        let hidden = HomeRowChoice.shared.map(\.id).filter { !ids.contains($0) }
        visibility.applyRows(.init(enabled: ids, disabled: hidden), choices: choices)

        try await withWindow {
            ScrollView {
                HomeRowsSettingsView(libraries: libraries, accounts: [], visibility: visibility)
                    .padding(24)
            }
            #if os(tvOS)
            .frame(width: 1050)
            #endif
        } inspect: { window in
            let before = try await self.capture(window, name: "Home arranger original order")
            XCTAssertGreaterThan(try self.y("Alpha", in: before), try self.y("Beta", in: before))
            XCTAssertTrue(before.contains { $0.0.contains("Shared rows") })
            visibility.applyRows(.init(enabled: Array(ids.reversed()), disabled: hidden), choices: choices)
            let after = try await self.capture(window, name: "Home arranger reversed order")
            XCTAssertGreaterThan(try self.y("Beta", in: after), try self.y("Alpha", in: after))
            XCTAssertEqual(store.load().rowSections(choices: choices).enabled, Array(ids.reversed()))
        }
    }

    func testRowSubtitlesAndRanksRemainVisibleAtLargeTextSizes() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await withWindow {
                ScrollView {
                    LiftableReorderList(
                        sections: .init(enabled: ["Alpha", "Beta"], disabled: []),
                        disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                        isLifting: .constant(false),
                        row: {
                            .init(title: Text(verbatim: $0), subtitle: Text("Movies"))
                        }, onChange: { _ in }
                    )
                    .padding(30)
                }
                .environment(\.dynamicTypeSize, size)
                #if os(tvOS)
                .frame(width: 1050)
                #endif
            } inspect: { window in
                let text = try await self.capture(window, name: "Home row text size \(size)")
                XCTAssertGreaterThan(try self.y("Alpha", in: text), try self.y("Beta", in: text))
                XCTAssertEqual(text.filter { $0.0.contains("Movies") }.count, 2)
            }
        }
    }

    func testPresetActionsRemainSeparatedAtLargeTextSizes() async throws {
        let suite = "HomeRowPresets.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await withWindow {
                ScrollView {
                    HomeRowsSettingsView(libraries: [], accounts: [], visibility: visibility)
                        .padding(24)
                }
                .environment(\.dynamicTypeSize, size)
                #if os(tvOS)
                .frame(width: 1050)
                #endif
            } inspect: { window in
                let lines = try await self.capture(window, name: "Home presets text size \(size)")
                let text = lines.map(\.0).joined(separator: " ").replacingOccurrences(of: "- ", with: "-")
                XCTAssertTrue(text.contains("Use server-style rows"), text)
                XCTAssertTrue(text.contains("Use shared rows"), text)
                XCTAssertGreaterThan(
                    try self.y("Use server", in: lines),
                    try self.y("Use shared", in: lines)
                )
                XCTAssertGreaterThan(
                    try self.y("Use shared", in: lines),
                    try self.y("ROWS", in: lines)
                )
            }
        }
    }

    #if os(tvOS)
    func testAllHiddenNoticeStillProvidesANativeFocusTarget() async throws {
        try await withWindow {
            HomeContentNoticeView(notice: .noHomeRows, onReload: {})
        } inspect: { window in
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController)
            let deadline = ContinuousClock.now + .seconds(3)
            while system.focusedItem == nil, ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                system.requestFocusUpdate(to: host)
                system.updateFocusIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotNil(system.focusedItem)
            let text = try await self.capture(window, name: "All Home rows hidden")
            XCTAssertTrue(text.contains { $0.0.contains("Reload") })
        }
    }
    #endif

    private func withWindow<Content: View>(
        @ViewBuilder content: () -> Content,
        inspect: (UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView:
            content()
                .environment(\.themePalette, ThemePalette.dark)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US"))
                .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await inspect(window)
    }

    private func capture(_ window: UIWindow, name: String) async throws -> [(String, CGRect)] {
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { result in
            result.topCandidates(1).first.map { ($0.string, result.boundingBox) }
        }
    }

    private func y(_ name: String, in lines: [(String, CGRect)]) throws -> CGFloat {
        try XCTUnwrap(lines.first { $0.0.contains(name) }, lines.map(\.0).joined(separator: " | ")).1.midY
    }
}

#if os(iOS)
private actor HomeSettingsLibraryProvider: MediaProvider {
    let session: UserSession
    let isOffline: Bool
    let kind = ProviderKind.jellyfin
    private(set) var libraryRequests = 0

    init(name: String, isOffline: Bool) {
        self.isOffline = isOffline
        session = UserSession(
            server: MediaServer(
                id: name, name: name,
                baseURL: URL(string: "https://home-settings.example.test")!, provider: .jellyfin
            ),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
        )
    }

    func libraries() async throws -> [MediaLibrary] {
        libraryRequests += 1
        if isOffline { throw AppError.serverUnreachable }
        return [MediaLibrary(id: "movies", title: "Movies", kind: .movie)]
    }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
#endif
