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
        if arguments.contains("--landscape") { model.settings.playback.settings.orientation = .landscape }
        if arguments.contains("--portrait") { model.settings.playback.settings.orientation = .portrait }
        _model = State(initialValue: model)
    }

    var body: some View {
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
        .plozziOSPlayerCover(item: $request, orientation: model.settings.playback.settings.orientation) {
            request, orientation in
            PlozziOSPlayerView(
                request: request, provider: RotationProvider(probe: probe), orientation: orientation
            )
            .overlay(alignment: .topTrailing) {
                VStack {
                    Text("Loads \(probe.count)").accessibilityIdentifier("rotation-load-count")
                    Text(orientation.isLocked ? "locked" : "auto")
                        .accessibilityIdentifier("rotation-lock-state")
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
        .environment(model)
        .environment(hero)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .environment(\.locale, Locale(identifier: "en_US"))
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

private struct RotationProvider: MediaProvider {
    static let media = MediaItem(
        id: "rotation", title: "Rotation fixture", kind: .video, runtime: 180,
        allowsTitleBasedMetadataMatching: false
    )
    let probe: RotationLoadProbe
    let kind = ProviderKind.jellyfin
    let session = UserSession(
        server: MediaServer(
            id: "rotation", name: "Local fixture", baseURL: URL(string: "https://example.invalid")!,
            provider: .jellyfin
        ),
        userID: "fixture", userName: "Fixture", deviceID: "fixture", accessToken: ""
    )
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
        return PlaybackRequest(item: Self.media, streamURL: try await Self.movie())
    }
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
