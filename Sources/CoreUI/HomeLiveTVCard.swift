#if canImport(SwiftUI)
import CoreModels
import SwiftUI

private struct HomeLiveTVSnapshotKey: EnvironmentKey {
    static let defaultValue = HomeLiveTVSnapshot.empty
}

private struct HomeLiveTVSelectionKey: EnvironmentKey {
    static let defaultValue: @MainActor (HomeLiveTVRoute) -> Void = { _ in }
}

public extension EnvironmentValues {
    var homeLiveTVSnapshot: HomeLiveTVSnapshot {
        get { self[HomeLiveTVSnapshotKey.self] }
        set { self[HomeLiveTVSnapshotKey.self] = newValue }
    }
    var openHomeLiveTV: @MainActor (HomeLiveTVRoute) -> Void {
        get { self[HomeLiveTVSelectionKey.self] }
        set { self[HomeLiveTVSelectionKey.self] = newValue }
    }
}

/// An intentionally non-VOD card: no progress, watchlist menu, image request or
/// preview. The broadcast badge makes its one-press tune behavior explicit.
public struct HomeLiveTVCard: View {
    public let channel: HomeLiveTVChannel
    public let width: CGFloat
    private let onFocused: ((HomeLiveTVChannel) -> Void)?
    @Environment(\.themePalette) private var palette
    @Environment(\.openHomeLiveTV) private var open
    @FocusState private var isFocused: Bool

    public init(
        channel: HomeLiveTVChannel, width: CGFloat,
        onFocused: ((HomeLiveTVChannel) -> Void)? = nil
    ) {
        self.channel = channel
        self.width = width
        self.onFocused = onFocused
    }

    public var body: some View {
        Button { open(channel.route) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Live", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer(minLength: 0)
                    if channel.number > 0 {
                        Text(verbatim: String(channel.number)).monospacedDigit()
                    }
                }
                .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(verbatim: channel.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: channel.sourceName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isFocused ? .black.opacity(0.7) : palette.secondaryText)
            }
            .padding(width * 0.055)
            .frame(width: width, height: width * 9 / 16, alignment: .leading)
            .foregroundStyle(isFocused ? .black : palette.primaryText)
            .background(isFocused ? Color.white : palette.cardSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isFocused ? Color.white : palette.cardBorder, lineWidth: isFocused ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused { onFocused?(channel) }
        }
        .accessibilityLabel(Text(verbatim: channel.name) + Text(", Live TV"))
        .accessibilityHint("Watch this channel")
    }
}
#endif
