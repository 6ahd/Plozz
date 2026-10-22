#if os(iOS)
import CoreModels
import CoreUI
@testable import FeaturePlayback
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class PlayerChapterPresentationTests: XCTestCase {
    func testOverflowingChaptersOpenWithClearTopAndSideInsets() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let player = PlayerViewModel(provider: ChapterPresentationProvider(), itemID: "fixture")
        await player.load()
        player.controls.infoCard.chapters = (0..<20).map {
            MediaChapter(start: Double($0) * 180, title: "Scene \($0 + 1)")
        }
        player.controls.duration = 3_600
        for size in [CGSize(width: 320, height: 568), .init(width: 568, height: 320), .init(width: 1024, height: 768)] {
            for chapterIndex in [0, 5] {
                player.controls.currentSeconds = Double(chapterIndex) * 180 + 10
                let probe = ChapterLayoutProbe()
                let host = UIHostingController(rootView:
                    MobileChapterFixture(player: player, size: size, probe: probe)
                        .environment(\.colorScheme, .dark)
                        .environment(\.locale, Locale(identifier: "en_US"))
                )
                host.safeAreaRegions = []
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(500))
                let metrics = PlayerCardMetrics.resolved(forWidth: size.width, height: size.height)
                let scroll = try XCTUnwrap(scrollViews(in: host.view).first {
                    metrics.isVertical ? $0.contentSize.height > $0.bounds.height + 100
                        : $0.contentSize.width > $0.bounds.width + 100 && $0.bounds.height > 64
                })
                let frame = scroll.convert(scroll.bounds, to: window)
                XCTAssertEqual(frame.minX - probe.panelFrame.minX, metrics.contentPadding, accuracy: 1)
                XCTAssertEqual(frame.minY - probe.panelFrame.minY, metrics.contentPadding, accuracy: 1)
                XCTAssertEqual(probe.panelFrame.maxX - frame.maxX, metrics.contentPadding, accuracy: 1)
                XCTAssertEqual(probe.panelFrame.maxY - frame.maxY, metrics.contentPadding, accuracy: 1)

                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let recognition = VNRecognizeTextRequest()
                recognition.recognitionLevel = .accurate
                recognition.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
                let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(text.contains("Scene \(chapterIndex + 1)"), "The current chapter must be visible on opening: \(text)")
                let topInset = CGRect(
                    x: probe.panelFrame.minX + 1, y: probe.panelFrame.minY + 1,
                    width: probe.panelFrame.width - 2, height: metrics.contentPadding - 2
                )
                XCTAssertLessThan(try brightestPixel(in: image, rect: topInset), 20,
                                  "No enclosing panel or scrolled-off chapter may occupy the top gutter.")
                let attachment = XCTAttachment(image: image)
                attachment.name = "Overflowing chapters \(Int(size.width))x\(Int(size.height)) start \(chapterIndex + 1)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        await player.stop()
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func brightestPixel(in image: UIImage, rect: CGRect) throws -> UInt8 {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: rect.integral))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
            bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(crop.width * crop.height * 4)).filter { $0 % 4 != 3 }.map { bytes[$0] }.max() ?? 0
    }

    func testChapterCardsAndConditionalTabsFitPhoneAndTabletWindows() async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let player = PlayerViewModel(provider: ChapterPresentationProvider(), itemID: "fixture")
        await player.load()
        let chapters: [MediaChapter] = [
            .init(start: 0, title: "Opening"), .init(start: 180, title: "The journey"), .init(start: 360)
        ]
        player.controls.duration = 600
        for size in [CGSize(width: 320, height: 568), .init(width: 568, height: 320), .init(width: 1024, height: 768)] {
            for reduced in [false, true] {
                let probe = ChapterLayoutProbe()
                player.controls.infoCard.chapters = chapters
                let host = UIHostingController(rootView:
                    MobileChapterFixture(player: player, size: size, probe: probe)
                        .environment(\.plozzReducePanelGlass, reduced)
                        .environment(\.colorScheme, .dark)
                        .environment(\.locale, Locale(identifier: "en_US"))
                )
                host.safeAreaRegions = []
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(500))
                XCTAssertGreaterThan(probe.stripHeight, 20)
                XCTAssertLessThan(probe.stripHeight, 64, "Horizontal scrolling must not expand the tab strip vertically.")
                let chapterTab = try XCTUnwrap(player.controls.subtitleLayout.frame(for: .tab("chapters")))
                XCTAssertTrue(window.bounds.contains(chapterTab))
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let recognition = VNRecognizeTextRequest()
                recognition.recognitionLevel = .accurate
                recognition.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
                let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                for expected in ["Chapters", "Opening", "The journey", "Chapter 3"] {
                    XCTAssertTrue(text.localizedCaseInsensitiveContains(expected), "Missing chapter content: \(text)")
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Chapters \(Int(size.width))x\(Int(size.height)) \(reduced ? "reduced" : "native")"
                attachment.lifetime = .keepAlways
                add(attachment)
                player.controls.infoCard.chapters = []
                try await Task.sleep(for: .milliseconds(200))
                XCTAssertNil(player.controls.subtitleLayout.frame(for: .tab("chapters")))
            }
        }
        await player.stop()
    }
}

@MainActor
private final class ChapterLayoutProbe {
    var stripHeight: CGFloat = 0
    var panelFrame: CGRect = .zero
}

private struct MobileChapterFixture: View {
    let player: PlayerViewModel
    let size: CGSize
    let probe: ChapterLayoutProbe
    @FocusState private var focus: PlayerControls.FocusSlot?

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            PlayerTouchCardStrip(
                model: player.controls, availableSize: size, isCardOpen: .constant(false), player: player,
                onRestart: {}, onNextEpisode: {}, onPreviousEpisode: {}
            )
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { probe.stripHeight = $0 }
            PlayerChapterPanel(model: player.controls, spoilerSettings: .default, focus: $focus) { _ in }
                .environment(\.playerCardMetrics, .resolved(forWidth: size.width, height: size.height))
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { probe.panelFrame = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

private struct ChapterPresentationProvider: MediaProvider {
    let kind = ProviderKind.jellyfin
    let session = UserSession(
        server: .init(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.invalid")!, provider: .jellyfin),
        userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
    )
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
#endif
