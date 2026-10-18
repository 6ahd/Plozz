import CoreUI
@testable import FeaturePlayback
import SwiftUI

struct PlayerGlassAppearanceFixture: View {
    @State private var light = false
    @State private var reduced = false
    @State private var whiteVideo = true

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Button(light ? "Dark" : "Light") { light.toggle() }.accessibilityIdentifier("appearance-theme")
                Button(reduced ? "Glass" : "Fallback") { reduced.toggle() }.accessibilityIdentifier("appearance-effects")
                Button(whiteVideo ? "Black video" : "White video") { whiteVideo.toggle() }
                    .accessibilityIdentifier("appearance-video")
            }
            .buttonStyle(.borderedProminent)
            HStack(spacing: 24) {
                Button {} label: { Image(systemName: "plus").font(.title) }
                    .buttonStyle(PlayerGlassCircleButtonStyle(diameter: 80))
                    .accessibilityIdentifier("appearance-circle")
                Button("Info") {}
                    .buttonStyle(PlayerTabButtonStyle(focused: false))
                    .accessibilityIdentifier("appearance-tab")
                PlayerControlButton("Play", systemImage: "play.fill") {}
                    .accessibilityIdentifier("appearance-native-button")
                PlayerControlButton("Prominent", systemImage: "play.fill", prominent: true) {}
                    .accessibilityIdentifier("appearance-prominent")
            }
            PlayerScrubTrackSurface(height: 20)
                .frame(width: 500)
                .accessibilityElement()
                .accessibilityIdentifier("appearance-track")
            Text(verbatim: "Player panel")
                .font(.title)
                .foregroundStyle(Color.primary)
                .frame(width: 500, height: 120)
                .playerPanelBackground()
                .accessibilityIdentifier("appearance-panel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(whiteVideo ? Color.white : .black)
        .environment(\.colorScheme, light ? .light : .dark)
        .environment(\.themePalette, light ? .light : .dark)
        .environment(\.plozzReduceTransparency, reduced)
        .preferredColorScheme(light ? .light : .dark)
    }
}
