import CoreModels
import CoreUI
#if os(tvOS)
@testable import FeatureHome
#endif
import FeatureSettings
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class HomeRowArrangementHostedTests: XCTestCase {
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
        let ids = libraries.map { HomeRowID.library($0.key, kind: .recentlyAdded) }
        let hidden = HomeRowChoice.shared.map(\.id)
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
            XCTAssertTrue(before.contains { $0.0 == "Custom" })
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

    func testPresetControlsRemainSeparatedAtLargeTextSizes() async throws {
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
                let text = lines.map(\.0).joined(separator: " ")
                XCTAssertTrue(text.contains("Server defaults"), text)
                XCTAssertTrue(text.contains("Combined rows"), text)
                XCTAssertGreaterThan(
                    try self.y("Server", in: lines),
                    try self.y("Combined", in: lines)
                )
                XCTAssertGreaterThan(
                    try self.y("Combined", in: lines),
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
