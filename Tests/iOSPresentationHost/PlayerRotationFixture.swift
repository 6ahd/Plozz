import AVFoundation
import CoreModels
import CoreUI
import FeatureHomeCore
import Observation
import SwiftUI
import UIKit
@testable import AppShelliOS
@testable import FeaturePlayback

@MainActor
@Observable
final class RotationLoadProbe {
    var count = 0
    var interfaceOrientation = 0
    private var server: IPTVTestHTTPServer?
    private var streamingURL: URL?

    func playbackURL(file: URL, streaming: Bool) async throws -> URL {
        guard streaming else { return file }
        if let streamingURL { return streamingURL }
        let bytes = try Data(contentsOf: file)
        let server = try IPTVTestHTTPServer { request in
            var headers = ["Content-Type": "video/quicktime", "Accept-Ranges": "bytes"]
            guard let range = request.components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("range: bytes=") }) else {
                return .init(data: bytes, headers: headers)
            }
            let bounds = range.split(separator: "=").last?.split(separator: "-", omittingEmptySubsequences: false)
            guard let bounds, bounds.count == 2, let start = Int(bounds[0]),
                  start >= 0, start < bytes.count else {
                return .init(status: 416, headers: ["Content-Range": "bytes */\(bytes.count)"])
            }
            let end = min(Int(bounds[1]) ?? (bytes.count - 1), bytes.count - 1)
            guard end >= start else {
                return .init(status: 416, headers: ["Content-Range": "bytes */\(bytes.count)"])
            }
            headers["Content-Range"] = "bytes \(start)-\(end)/\(bytes.count)"
            return .init(data: bytes.subdata(in: start..<(end + 1)), status: 206, headers: headers)
        }
        self.server = server
        let url = try await server.start().appendingPathComponent("rotation-fixture.mov")
        streamingURL = url
        return url
    }
}

struct PlayerRotationFixture: View {
    @State private var model: PlozziOSAppModel
    @State private var hero = HeroTrailerController()
    @State private var probe = RotationLoadProbe()
    @State private var request: PlozziOSPlaybackRequest?

    init() {
        SyncSetupFeatureFlag().isEnabled = false
        let model = PlozziOSAppModel()
        model.settings.playback.settings = .default
        model.settings.playback.settings.useCommunityMarkers = false
        model.settings.playback.settings.syncWatchAcrossServers = false
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--auto") { model.settings.playback.settings.orientation = .auto }
        if arguments.contains("--portrait") { model.settings.playback.settings.orientation = .portrait }
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--nested-player-presentation") {
                TabView {
                    NavigationStack { playerSurface.navigationTitle("Fixture") }
                        .tabItem { Label("Home", systemImage: "house") }
                }
            } else {
                playerSurface
            }
        }
        .environment(model)
        .environment(hero)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private var playerSurface: some View {
        openButton.plozziOSPlayerCover(item: $request, orientation: model.settings.playback.settings.orientation) {
            request, orientation in
            player(request: request, orientation: orientation)
        }
    }

    private var openButton: some View {
        VStack {
            Button("Open rotation player") {
                request = .init(
                    item: RotationProvider.media, startPosition: 0,
                    versionPreferences: model.versionPreferences
                )
            }
            Text(model.settings.playback.settings.orientation.rawValue)
                .accessibilityIdentifier("saved-orientation")
        }
    }

    private func player(
        request: PlozziOSPlaybackRequest, orientation: PlozziOSPlayerOrientation
    ) -> some View {
        PlozziOSPlayerView(
            request: request, provider: RotationProvider(probe: probe), orientation: orientation
        )
        .overlay(alignment: .topTrailing) {
            VStack {
                Text("Loads \(probe.count)").accessibilityIdentifier("rotation-load-count")
                Text("\(probe.interfaceOrientation)").accessibilityIdentifier("rotation-interface-orientation")
            }
            .foregroundStyle(.white)
        }
        .task {
            while !Task.isCancelled {
                if let window = orientation.host?.view.window {
                    markVideo(in: window)
                    let value = window.windowScene?.effectiveGeometry.interfaceOrientation.rawValue ?? 0
                    if probe.interfaceOrientation != value {
                        probe.interfaceOrientation = value
                    }
                }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
        }
    }

    @MainActor
    private func markVideo(in view: UIView) {
        if view is VideoPresentationView {
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "rotation-video-surface"
        }
        for child in view.subviews { markVideo(in: child) }
    }
}

private struct RotationProvider: MediaProvider, StreamingQualityProviding {
    private static var failsPlayback: Bool {
        ProcessInfo.processInfo.arguments.contains("--failed-player-fixture")
    }
    private static var embyStreaming: Bool {
        ProcessInfo.processInfo.arguments.contains("--emby-streaming-fixture")
    }
    static var media: MediaItem {
        MediaItem(
            id: "rotation", title: "Rotation fixture", kind: embyStreaming || failsPlayback ? .movie : .video, runtime: 180,
            allowsTitleBasedMetadataMatching: false
        )
    }
    let probe: RotationLoadProbe
    var kind: ProviderKind { Self.failsPlayback ? .silo : Self.embyStreaming ? .emby : .jellyfin }
    var session: UserSession {
        UserSession(
            server: MediaServer(
                id: "rotation", name: "Local fixture", baseURL: URL(string: "https://example.invalid")!,
                provider: kind
            ),
            userID: "fixture", userName: "Fixture", deviceID: "fixture", accessToken: ""
        )
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { Self.media }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest {
        await MainActor.run { probe.count += 1 }
        if Self.failsPlayback {
            throw StreamingQualityError.serverRefusal("Synthetic playback preparation failure.")
        }
        let file = try await Self.movie()
        let url = try await probe.playbackURL(file: file, streaming: Self.embyStreaming)
        return PlaybackRequest(item: Self.media, streamURL: url)
    }
    func playbackInfo(
        for itemID: String, mediaSourceID: String?, forceTranscode: Bool,
        streaming: StreamingPlaybackOptions
    ) async throws -> PlaybackRequest {
        try await playbackInfo(for: itemID)
    }
    func releaseStreamingSession(_ request: PlaybackRequest) async {}
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }

    private static func movie() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-fixture.mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let source = Bundle.main.url(forResource: "four-three", withExtension: "mp4") else {
            throw AppError.notFound
        }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        for index in 0..<90 {
            try await composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: asset,
                at: CMTimeMultiply(duration, multiplier: Int32(index))
            )
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw AppError.notFound
        }
        try await exporter.export(to: url, as: .mov)
        return url
    }
}
