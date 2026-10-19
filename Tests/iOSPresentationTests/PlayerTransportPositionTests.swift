#if os(iOS)
@testable import AppShelliOS
import CoreModels
import CoreUI
import EnginePlozzigen
@testable import FeaturePlayback
import SwiftUI
import UIKit
import XCTest

@MainActor
final class PlayerTransportPositionTests: XCTestCase {
    func testTransportIsCenteredOnTheVideoAfterResizing() async throws {
        let model = PlayerViewModel(provider: LayoutProvider(), itemID: "fixture")
        model.controls.duration = 3600
        model.controls.currentSeconds = 600
        model.controls.title = "A title"
        model.controls.subtitle = "Season 1, Episode 2"
        model.controls.intendsPause = true
        try await assertCentered(
            PlozziOSPlayerControlsOverlay(
                viewModel: model, keyboardActions: PlozziOSPlayerKeyboardActions(),
                hasVersions: false, versionsPresented: false, onShowVersions: {}, onClose: {}
            ), label: "VOD", bottomFrame: { model.controls.subtitleLayout.frame(for: .transport) }
        )
    }

    func testLiveTransportUsesTheSameVideoCenterInPortraitAndLandscape() async throws {
        let input = LiveChannelInput.stream(
            url: try XCTUnwrap(URL(string: "https://fixture.invalid/live.m3u8")), httpHeaders: [:]
        )
        let tracks = LiveChannelPlayerModel(engine: try PlozzigenVideoEngine(), input: input)
        defer { tracks.stop() }
        try await assertCentered(
            LiveLayoutFixture(input: input, tracks: tracks), label: "Live",
            bottomFrame: {
                [SubtitleControlsLayout.Region.title, .trackControls]
                    .compactMap { tracks.subtitles.controlsLayout.frame(for: $0) }
                    .reduce(nil as CGRect?) { $0?.union($1) ?? $1 }
            }
        )
    }

    private func assertCentered(
        _ content: some View, label: String, bottomFrame: () -> CGRect?
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: content
            .environment(\.plozzReduceTransparency, true)
            .environment(\.themePalette, .light)
            .environment(\.colorScheme, .light)
            .background(.black)
        )
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for size in [
            CGSize(width: 956, height: 440), CGSize(width: 440, height: 956),
            CGSize(width: 852, height: 393), CGSize(width: 393, height: 852),
            CGSize(width: 1024, height: 768), CGSize(width: 768, height: 1024)
        ] {
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(500))
            let bottom = try XCTUnwrap(bottomFrame())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(label) centered on video \(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways
            add(attachment)
            let bitmap = try pixels(image)
            func bright(x: Int, y: Int) -> Bool {
                let offset = (y * Int(size.width) + x) * 4
                return min(bitmap[offset], bitmap[offset + 1], bitmap[offset + 2]) > 180
            }
            let centerRows = (Int(size.height / 2 - 50)..<Int(size.height / 2 + 50)).filter {
                bright(x: Int(size.width / 2) + 16, y: $0)
            }
            let centerY = CGFloat(try XCTUnwrap(centerRows.first) + XCTUnwrap(centerRows.last) + 1) / 2
            XCTAssertEqual(centerY, size.height / 2, accuracy: 1.5,
                           "Transport must match the native player's video center.")
            let compact = PlayerTouchLayout.usesCompactTransport(contentHeight: size.height - 48)
            XCTAssertLessThan(centerY + (compact ? 22 : 46), bottom.minY, "Transport must stay above bottom controls.")
            let offset = compact ? 64 : Int(78 + PlayerTouchLayout.transportSpacing(
                availableWidth: size.width - 42, portrait: size.height > size.width
            ))
            for offset in [-offset, 0, offset] {
                let x = Int(size.width / 2) + offset
                let y = Int(centerY)
                let darkPixels = ((y - 15)..<(y + 15)).reduce(0) { total, row in
                    total + ((x - 15)..<(x + 15)).filter { column in
                        bitmap[(row * Int(size.width) + column) * 4] < 60
                    }.count
                }
                XCTAssertGreaterThan(darkPixels, 50, "\(label): all three icons need dark ink on light fallback.")
            }
        }
    }

    private struct LiveLayoutFixture: View {
        let input: LiveChannelInput
        let tracks: LiveChannelPlayerModel
        @FocusState private var focus: LiveChannelControl?
        private let now = Date()

        var body: some View {
            LiveChannelOverlay(
                title: "Sample Channel", logoURL: nil, plozzChannelID: nil, channelID: "sample", input: input,
                program: .init(title: "Evening News", start: now.addingTimeInterval(-900), end: now.addingTimeInterval(900)),
                earlierPrograms: [], libraryItem: nil, openLibraryItem: nil, phase: .playing,
                isAtLiveEdge: true, behindLiveSeconds: 0, canPause: true, canGoLive: true,
                seekWindowSeconds: 3600, onSeekBy: { _ in }, onSeekBehindLive: { _ in },
                focus: $focus, onClose: {}, onPrevious: {}, onPlayPause: {}, onGoLive: {}, onNext: {},
                onMultiview: nil, guideContent: nil, pendingGuideOpen: false, consumeGuideOpen: {},
                onGuideCardChange: { _ in }, loadOnNow: { [] }, onTuneChannel: nil,
                tracks: tracks, diagnosticsEnabled: false, toggleDiagnostics: {},
                onTracksPresentationChange: { _ in }, onControlActivity: {}, onDismissControls: {}
            )
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}

private struct LayoutProvider: MediaProvider {
    let kind = ProviderKind.jellyfin
    let session = UserSession(
        server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.invalid")!,
                            provider: .jellyfin),
        userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
    )
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        throw AppError.notFound
    }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
#endif
