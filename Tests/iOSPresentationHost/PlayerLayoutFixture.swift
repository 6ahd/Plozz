import AVKit
import CoreModels
import CoreUI
import SwiftUI
@testable import AppShelliOS
@testable import FeaturePlayback

struct PlayerLayoutFixture: View {
    @State private var model: PlayerViewModel
    @State private var timelineSampleIndex = 0
    @State private var scrubStarts = 0

    init() {
        let provider = PlayerLayoutProvider()
        let episode = MediaItem(id: "layout", title: "Mud", kind: .episode, seriesID: "series")
        let playlist = VideoPlaylistPlaybackContext(
            origin: .init(playlistID: "playlist", accountID: "layout", index: 0, totalCount: 1, item: episode),
            provider: provider
        )
        let model = PlayerViewModel(
            provider: provider, itemID: episode.id, episodeItem: episode, playlistContext: playlist
        )
        model.controls.duration = ProcessInfo.processInfo.arguments.contains("--long-video") ? 5_400 : 1_200
        model.controls.currentSeconds = ProcessInfo.processInfo.arguments.contains("--timeline-rollovers") ? 0 : 600
        model.controls.bufferedSeconds = 900
        model.controls.title = "Wayward"
        model.controls.subtitle = "S1 E4 - Mud"
        model.controls.intendsPause = !ProcessInfo.processInfo.arguments.contains("--playing")
        model.controls.isScrubbing = ProcessInfo.processInfo.arguments.contains("--scrubbing")
        model.controls.scrubSeconds = model.controls.currentSeconds
        model.controls.infoCard.cast = [MediaPerson(id: "actor", name: "Actor", role: "Character")]
        _model = State(initialValue: model)
    }

    private struct PlayerLayoutProvider: MediaProvider {
        let kind = ProviderKind.jellyfin
        let session = UserSession(
            server: MediaServer(id: "layout", name: "Layout", baseURL: URL(string: "https://fixture.invalid")!,
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

    var body: some View {
        ZStack {
            (ProcessInfo.processInfo.arguments.contains("--white-video") ? Color.white : .black)
                .ignoresSafeArea()
            if ProcessInfo.processInfo.arguments.contains("--native-avkit") {
                NativePlayerGlassFixture(showsControls: true).ignoresSafeArea()
            } else {
                if ProcessInfo.processInfo.arguments.contains("--video") {
                    NativePlayerGlassFixture(showsControls: false).ignoresSafeArea()
                }
                PlozziOSPlayerControlsOverlay(
                    viewModel: model, keyboardActions: PlozziOSPlayerKeyboardActions(),
                    hasVersions: false, versionsPresented: false, onShowVersions: {}, onClose: {}
                )
            }
        }
        .statusBarHidden()
        .onChange(of: model.controls.isScrubbing) { _, active in
            if active { scrubStarts += 1 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player-layout-fixture")
        .accessibilityValue("scrubbing:\(model.controls.isScrubbing),starts:\(scrubStarts)")
        .environment(\.themePalette, light ? .light : .dark)
        .environment(\.colorScheme, light ? .light : .dark)
        .preferredColorScheme(light ? .light : .dark)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .overlay(alignment: .topTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--timeline-rollovers") {
                Button("Advance time") {
                    let duration = model.controls.duration
                    let samples = [0, 59, 60, 599, 600, 1_799, 1_800, 3_599, 3_600, duration - 1, duration]
                        .filter { $0 <= duration }
                    timelineSampleIndex = min(timelineSampleIndex + 1, samples.count - 1)
                    model.controls.currentSeconds = samples[timelineSampleIndex]
                }
                .accessibilityIdentifier("fixture-next-time")
                .accessibilityValue("\(timelineSampleIndex)")
                .padding(.top, 110)
            }
        }
    }

    private var light: Bool { ProcessInfo.processInfo.arguments.contains("--light") }
}

private struct NativePlayerGlassFixture: UIViewControllerRepresentable {
    let showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        guard let url = Bundle.main.url(forResource: "four-three", withExtension: "mp4") else {
            preconditionFailure("Missing local player reference video.")
        }
        controller.player = AVPlayer(url: url)
        controller.showsPlaybackControls = showsControls
        controller.allowsVideoFrameAnalysis = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
