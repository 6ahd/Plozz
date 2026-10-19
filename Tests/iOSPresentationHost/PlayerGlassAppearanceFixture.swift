import CoreUI
@testable import FeaturePlayback
import SwiftUI

struct PlayerGlassAppearanceFixture: View {
    @State private var light = false
    @State private var reduced = false
    @State private var whiteVideo = true
    @State private var leftPresses = 0
    @State private var rightPresses = 0

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
            PlayerGlassControlGroup {
                Button { leftPresses += 1 } label: { Image(systemName: "captions.bubble") }
                    .buttonStyle(PlayerGlassCircleButtonStyle(diameter: 44))
                    .accessibilityIdentifier("appearance-group-left")
                    .accessibilityValue("\(leftPresses)")
                Button { rightPresses += 1 } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(PlayerGlassCircleButtonStyle(diameter: 44))
                    .accessibilityIdentifier("appearance-group-right")
                    .accessibilityValue("\(rightPresses)")
            }
            .accessibilityIdentifier("appearance-group")
            PlayerScrubTrackSurface(height: 20)
                .frame(maxWidth: 500)
                .accessibilityElement()
                .accessibilityIdentifier("appearance-track")
            Text(verbatim: "Player panel")
                .font(.title)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: 500)
                .frame(height: 120)
                .playerPanelBackground()
                .accessibilityIdentifier("appearance-panel")
            if #available(iOS 26.0, *) {
                Text(verbatim: "Player panel")
                    .font(.title)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: 500)
                    .frame(height: 120)
                    .background {
                        Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32))
                    }
                    .accessibilityIdentifier("appearance-reference")
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(whiteVideo ? Color.white : .black)
        .environment(\.colorScheme, light ? .light : .dark)
        .environment(\.themePalette, light ? .light : .dark)
        .environment(\.plozzReduceTransparency, reduced)
        .preferredColorScheme(light ? .light : .dark)
    }
}
