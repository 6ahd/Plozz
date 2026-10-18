#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

struct StreamingPlaybackLoadingView: View {
    let options: StreamingPlaybackOptions
    let provider: String // l10n:content — provider brand
    let phase: StreamingPreparationPhase
    let transcoding: Bool
    let h264Fallback: Bool
    let hevcFallback: Bool

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(phase.message(
                provider: provider, transcoding: transcoding,
                usingH264Fallback: h264Fallback, usingHEVCFallback: hevcFallback
            ))
                .font(.headline)
            Text(options.quality.title).font(.subheadline)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 460)
        .padding(20)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("streaming-preparation")
        .allowsHitTesting(false)
    }
}

struct StreamingPlaybackFailureView: View {
    let message: LocalizedStringResource
    let report: PlaybackDiagnosticReport?
    let onChangeQuality: (() -> Void)?
    let onChangeVersion: (() -> Void)?
    let onPlaySDRVersion: (() -> Void)?
    let onPlayOriginal: (() -> Void)?
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    @State private var confirmsOriginal = false

    var body: some View {
        PlaybackFailureView(message: message, report: report) {
            if let onRetry {
                Button("Retry", action: onRetry)
                    .plozzActionButton(role: .primary)
                    .accessibilityIdentifier("playback-failure-retry")
            }
            if onChangeVersion != nil || onChangeQuality != nil || onPlaySDRVersion != nil || onPlayOriginal != nil {
                Menu {
                    if let onChangeVersion {
                        Button("Version", systemImage: "rectangle.stack", action: onChangeVersion)
                    }
                    if let onChangeQuality {
                        Button("Quality", systemImage: "slider.horizontal.3", action: onChangeQuality)
                    }
                    if let onPlaySDRVersion {
                        Button("Play an SDR version", systemImage: "rectangle.stack", action: onPlaySDRVersion)
                    }
                    if onPlayOriginal != nil {
                        Button("Play original quality") { confirmsOriginal = true }
                    }
                } label: {
                    Label("Playback options", systemImage: "slider.horizontal.3")
                }
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("player-failed-streaming-quality")
            }
            Button("Back", action: onDismiss)
                .plozzActionButton(role: .secondary)
                .accessibilityIdentifier("player-failed-back")
        }
        .confirmationDialog("Play original quality?", isPresented: $confirmsOriginal, titleVisibility: .visible) {
            if let onPlayOriginal {
                Button("Play original quality", action: onPlayOriginal)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This keeps your selected version but removes the streaming quality limit. It may use substantially more data, especially on cellular.")
        }
    }
}
#endif
