import AppShell
import CoreModels
import CoreUI
@testable import FeatureSettings
import SwiftUI

struct PlaybackReadAheadFixture: View {
    @State private var models = ProfileSettingsModel(namespace: "read-ahead-fixture")
    @AppStorage(PlaybackReadAheadStore.storageKey) private var selection = PlaybackReadAhead.default

    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-read-ahead") {
            PlaybackReadAheadStore().save(.default)
        }
    }

    var body: some View {
        NavigationStack {
            PlaybackDetailView(
                playback: models.playbackModel,
                subtitleBehavior: models.subtitleBehaviorModel,
                subtitleStyle: models.subtitleStyleModel,
                subtitlePolicy: models.subtitlePolicyModel,
                audioPolicy: models.audioPolicyModel,
                canDownloadSubtitles: false
            )
        }
        .environment(models.uiDensityModel)
        .environment(models.transparencyModel)
        .environment(\.themePalette, .dark)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))
        .overlay(alignment: .bottomLeading) {
            Text(verbatim: selection.rawValue)
                .accessibilityIdentifier("read-ahead-saved")
        }
    }
}
