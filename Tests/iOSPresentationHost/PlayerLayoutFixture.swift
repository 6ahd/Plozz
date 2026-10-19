import AVKit
import CoreModels
import CoreUI
import SwiftUI
@testable import AppShelliOS
@testable import FeaturePlayback

struct PlayerLayoutFixture: View {
    @State private var model: PlayerViewModel

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
        model.controls.duration = 3600
        model.controls.currentSeconds = 600
        model.controls.bufferedSeconds = 1440
        model.controls.title = "Wayward"
        model.controls.subtitle = "S1 E4 - Mud"
        model.controls.intendsPause = true
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
        .environment(\.themePalette, light ? .light : .dark)
        .environment(\.colorScheme, light ? .light : .dark)
        .preferredColorScheme(light ? .light : .dark)
        .environment(\.plozzMetrics, .touch(density: .standard))
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
