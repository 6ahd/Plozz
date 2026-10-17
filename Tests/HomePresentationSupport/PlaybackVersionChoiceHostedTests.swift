import CoreModels
import CoreUI
import FeatureHomeCore
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class PlaybackVersionChoiceHostedTests: XCTestCase {
    func testIntroductionHandsOffToNativeVersionChoicesWithoutStartingPlayback() async throws {
        #if os(tvOS)
        let layouts: [(CGFloat, DynamicTypeSize)] = [(1920, .large)]
        #else
        let layouts: [(CGFloat, DynamicTypeSize)] = [(320, .large), (768, .large), (390, .accessibility2)]
        #endif
        for (width, typeSize) in layouts {
            try await exercise(width: width, typeSize: typeSize)
        }
    }

    private func exercise(width: CGFloat, typeSize: DynamicTypeSize) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let suite = "version-choice-hosted-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let probe = VersionChoiceHostedProbe()
        let settings = PlaybackSettingsModel(store: PlaybackSettingsStore(defaults: defaults))
        let preferences = VersionPreferenceStore(defaults: defaults)
        let model = PlaybackVersionChoiceModel()
        let item = MediaItem(id: "movie", title: "Version fixture", kind: .movie, versions: [
            .init(id: "4k", fileName: "Example.2160p.REMUX-GROUP.mkv", height: 2160, sizeBytes: 42_000_000_000,
                  duration: 7_200, videoCodec: "hevc", videoRange: "HDR10",
                  audioCodec: "truehd", sourceMetadata: .init(audioLanguages: ["eng", "fra"])),
            .init(id: "1080", height: 1080, videoRange: "SDR")
        ])
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: width >= 768 ? 1080 : 844)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView:
            VersionChoiceHostedFixture(
                model: model, probe: probe, item: item, settings: settings, preferences: preferences
            )
            .environment(\.themePalette, .dark)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.dynamicTypeSize, typeSize)
        )
        window.makeKeyAndVisible()
        defer {
            model.cancel()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        try await waitUntil { model.prompt != nil }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        XCTAssertFalse(probe.disappeared, "Presenting the prompt must not disappear/cancel its playback owner.")
        XCTAssertNil(probe.selected)
        XCTAssertNil(probe.error)
        let introduction = try await visibleText(in: window, name: "version-introduction-\(Int(width))-\(typeSize)")
        for label in ["choose versions", "Ask every time", "Remember my choice", "Settings", "Cancel"] {
            XCTAssertTrue(introduction.localizedCaseInsensitiveContains(label), "Missing \(label): \(introduction)")
        }
        #if os(tvOS)
        XCTAssertNotNil(UIFocusSystem(for: window)?.focusedItem, "An introduction action must own native focus.")
        #endif
        let id = try XCTUnwrap(model.prompt?.id)
        model.chooseMode(.rememberChoice, promptID: id)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(probe.selected, "Choosing the mode alone must not select a file.")
        XCTAssertFalse(try XCTUnwrap(model.prompt).needsIntroduction)
        let choices = try await visibleText(in: window, name: "version-choice-\(Int(width))-\(typeSize)")
        for fact in ["Choose a version", "4K", "42 GB", "English", "French", "HEVC", "TrueHD"] {
            XCTAssertTrue(choices.contains(fact), "Missing \(fact): \(choices)")
        }
        #if os(tvOS)
        XCTAssertNotNil(UIFocusSystem(for: window)?.focusedItem, "The version picker must receive native focus.")
        #endif
        model.chooseVersion("4k", promptID: id)
        try await waitUntil { probe.selected != nil }
        XCTAssertEqual(probe.selected?.selectedVersionID, "4k")
        XCTAssertEqual(settings.settings.versionSelectionMode, .rememberChoice)
        XCTAssertFalse(probe.disappeared)
        XCTAssertNil(probe.error)
    }

    private func visibleText(in window: UIWindow, name: String) async throws -> String {
        var result = ""
        let scrolls = scrollViews(in: window).filter { !$0.isHidden && $0.window != nil }
        // Capture the initial layout and the bottom of each native scroll area,
        // including accessible text that does not fit a compact sheet at once.
        for index in 0...scrolls.count {
            if index > 0 {
                let scroll = scrolls[index - 1]
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
                let bottom = max(-scroll.adjustedContentInset.top,
                                 scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            result += " " + (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        return result
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "The native version-choice flow did not reach its expected state.")
    }
}

@MainActor @Observable
private final class VersionChoiceHostedProbe {
    var selected: MediaItem?
    var disappeared = false
    var error: String?
}

private struct VersionChoiceHostedFixture: View {
    let model: PlaybackVersionChoiceModel
    let probe: VersionChoiceHostedProbe
    let item: MediaItem
    let settings: PlaybackSettingsModel
    let preferences: VersionPreferenceStore

    var body: some View {
        Color.black.ignoresSafeArea()
            .task {
                do {
                    probe.selected = try await model.prepare(
                        item, provider: VersionChoiceHostedProvider(),
                        settings: settings, preferences: preferences
                    )
                } catch is CancellationError {
                } catch {
                    probe.error = String(describing: error)
                }
            }
            .onDisappear {
                probe.disappeared = true
                model.cancel()
            }
            .playbackVersionChoice(model)
    }
}

private struct VersionChoiceHostedProvider: MediaProvider {
    var kind: ProviderKind { .jellyfin }
    var session: UserSession {
        UserSession(
            server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://example.invalid")!, provider: kind),
            userID: "fixture", userName: "Fixture", deviceID: "fixture", accessToken: ""
        )
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest {
        XCTFail("The version introduction must not resolve a playback stream.")
        throw AppError.notFound
    }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
