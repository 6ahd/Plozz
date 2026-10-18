#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public extension View {
    func playbackVersionChoice(_ model: PlaybackVersionChoiceModel) -> some View {
        modifier(PlaybackVersionChoicePresentation(model: model))
    }
}

private struct PlaybackVersionChoicePresentation: ViewModifier {
    let model: PlaybackVersionChoiceModel

    func body(content: Content) -> some View {
        #if os(tvOS)
        // The player is already a full-screen presentation. A second cover
        // would disappear/cancel the playback owner while it waits for a choice.
        content
            .disabled(model.prompt != nil)
            .allowsHitTesting(model.prompt == nil)
            .accessibilityHidden(model.prompt != nil)
            .overlay {
                if model.prompt != nil {
                    GeometryReader { geometry in
                        ZStack {
                            PlozzDialogBackdrop()
                            ViewThatFits(in: .vertical) {
                                PlaybackVersionChoiceView(model: model)
                                    .fixedSize(horizontal: false, vertical: true)
                                PlaybackVersionChoiceView(model: model)
                            }
                            .frame(width: min(1_100, max(0, geometry.size.width - 64)))
                            .plozzSurface(.overlay, cornerRadius: 32)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("version-choice-dialog")
                            // Bound the proposal without stretching the card's surface.
                            .frame(maxHeight: min(860, max(0, geometry.size.height - 64)))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        #else
        content.plozzSheet(isPresented: Binding(
            get: { model.prompt != nil },
            set: { if !$0 { model.cancel() } }
        )) {
            PlaybackVersionChoiceView(model: model)
                .interactiveDismissDisabled()
        }
        #endif
    }
}

public struct PlaybackVersionChoiceView: View {
    let model: PlaybackVersionChoiceModel

    public init(model: PlaybackVersionChoiceModel) { self.model = model }

    public var body: some View {
        if let prompt = model.prompt {
            VStack(spacing: 0) {
                if prompt.needsIntroduction {
                    FirstUseChoiceView(
                        symbol: "square.stack",
                        title: "How would you like to choose versions?",
                        message: "Some videos have more than one version. Choose each time, including the next episode, or remember your choice for this movie or series.",
                        firstAction: "Ask every time",
                        secondAction: "Remember my choice",
                        footer: "If a remembered version isn't available, we'll ask again. Change this any time in Settings > Playback > Version selection.",
                        firstIdentifier: "version-choice-ask",
                        secondIdentifier: "version-choice-remember"
                    ) { ask in
                        model.chooseMode(ask ? .askEveryTime : .rememberChoice, promptID: prompt.id)
                    }
                } else {
                    PlaybackVersionChoiceList(prompt: prompt) {
                        model.chooseVersion($0, promptID: prompt.id)
                    }
                }
                Button("Cancel") { model.cancel() }
                    .plozzActionButton(role: .secondary)
                    .accessibilityIdentifier("version-choice-cancel")
                    .padding()
            }
            #if os(tvOS)
            .onExitCommand { model.cancel() }
            #endif
        }
    }
}

private struct PlaybackVersionChoiceList: View {
    let prompt: PlaybackVersionChoiceModel.Prompt
    let select: (String) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a version")
                    .font(.title.bold())
                    .foregroundStyle(palette.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: prompt.item.title)
                    .font(.headline)
                    .foregroundStyle(palette.secondaryText)
                ForEach(prompt.versions) { version in
                    Button { select(version.id) } label: {
                        PlaybackVersionChoiceLabel(presentation: .init(version, locale: locale))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            #if os(tvOS)
                            .environment(\.themePalette, focusedID == version.id ? .light : palette)
                            .environment(\.colorScheme, focusedID == version.id ? .light : colorScheme)
                            #endif
                    }
                    .plozzActionButton(role: .secondary)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .focused($focusedID, equals: version.id)
                    .accessibilityIdentifier("version-choice-\(version.id)")
                }
            }
            .padding(32)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        #if os(tvOS)
        .defaultFocus($focusedID, prompt.versions.first?.id, priority: .userInitiated)
        #endif
    }
}

private struct PlaybackVersionChoiceLabel: View {
    let presentation: MediaVersion.PickerPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = presentation.titleWithoutBadges {
                Text(verbatim: title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            } else if presentation.badges.isEmpty {
                Text("Original")
            }
            if !presentation.supplementalFactsWithoutBadges.isEmpty {
                Text(verbatim: presentation.supplementalFactsWithoutBadges.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let releaseName = presentation.releaseName {
                Text(verbatim: releaseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            if !presentation.badges.isEmpty {
                WrappingHStackLayout(spacing: 8, lineSpacing: 6) {
                    ForEach(presentation.badges) { badge in
                        MetadataMediaBadgeChip(badge: badge)
                    }
                }
                .environment(\.mediaBadgeScale, 0.85)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
