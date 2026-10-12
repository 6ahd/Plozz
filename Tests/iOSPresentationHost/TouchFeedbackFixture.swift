import SwiftUI
import FeaturePlayback
@testable import CoreUI

struct TouchFeedbackFixture: View {
    @State private var position: TimeInterval = 30
    @State private var duration: TimeInterval = 300
    @State private var events = 0
    @State private var previews = 0
    @State private var commits = 0

    var body: some View {
        VStack(spacing: 30) {
            PlayerTouchScrubBar(
                currentSeconds: position, duration: duration, bufferedFraction: 1,
                onScrub: { position = $0; previews += 1 },
                onScrubbingChanged: { if !$0 { commits += 1 } },
                feedback: TouchFeedback(
                    output: { _ in events += 1 },
                    isActive: { true }, now: { 0 }
                )
            )
            .accessibilityIdentifier("touch-scrubber")
            Text("Feedback \(events)").accessibilityIdentifier("feedback-count")
            Text("Previews \(previews)").accessibilityIdentifier("preview-count")
            Text("Commits \(commits)").accessibilityIdentifier("commit-count")
            Button("Playback tick") { position += 1 }
            Button("Unknown duration") { duration = 0 }
        }
        .padding(40)
        .preferredColorScheme(.dark)
    }
}
