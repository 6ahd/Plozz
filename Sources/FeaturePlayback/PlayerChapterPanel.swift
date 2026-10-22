#if canImport(SwiftUI) && canImport(UIKit)
import CoreModels
import CoreUI
import SwiftUI

struct PlayerChapterPanel: View {
    let model: PlayerControlsModel
    let spoilerSettings: SpoilerSettings
    @FocusState.Binding var focus: PlayerControls.FocusSlot?
    let onSelect: (MediaChapter) -> Void
    @Environment(\.playerCardMetrics) private var metrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(metrics.isVertical ? .vertical : .horizontal, showsIndicators: false) {
                if metrics.isVertical {
                    LazyVStack(spacing: 12) { chapters }
                } else {
                    LazyHStack(spacing: metrics.columnSpacing) { chapters }
                }
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #else
            .scrollClipDisabled(false)
            #endif
            // Keep the inset outside the scroll target, including on first open.
            .padding(metrics.contentPadding)
            .frame(height: metrics.cardHeight)
            .onAppear {
                if let id = MediaChapter.currentID(
                    in: model.infoCard.chapters, at: model.currentSeconds, duration: model.duration
                ) {
                    proxy.scrollTo(id, anchor: metrics.isVertical ? .top : .leading)
                }
            }
        }
        .accessibilityIdentifier("player-chapters")
    }

    private var chapters: some View {
        let entries = model.infoCard.chapters
        return ForEach(Array(entries.enumerated()), id: \.element.id) { index, chapter in
            PlayerChapterButton(
                chapter: chapter, number: index + 1,
                nextStart: entries.indices.contains(index + 1) ? entries[index + 1].start : nil,
                model: model,
                spoilerSettings: spoilerSettings,
                focus: $focus
            ) {
                onSelect(chapter)
            }
            .id(chapter.id)
        }
    }
}

/// Only visible chapter buttons observe the playhead, not the player/tab root.
private struct PlayerChapterButton: View {
    let chapter: MediaChapter
    let number: Int
    let nextStart: TimeInterval?
    let model: PlayerControlsModel
    let spoilerSettings: SpoilerSettings
    @FocusState.Binding var focus: PlayerControls.FocusSlot?
    let action: () -> Void
    @Environment(\.playerCardMetrics) private var metrics
    @Environment(\.playerControlForeground) private var foreground

    private var isCurrent: Bool {
        let time = model.currentSeconds
        return time.isFinite && time >= chapter.start
            && (nextStart.map { time < $0 } ?? true)
            && (!model.duration.isFinite || model.duration <= 0 || time < model.duration)
    }

    private var hidesText: Bool {
        model.infoCard.artworkItem.map(spoilerSettings.shouldHideText(for:)) ?? false
    }

    private var hidesImage: Bool {
        model.infoCard.artworkItem.map(spoilerSettings.shouldHideThumbnail(for:)) ?? false
    }

    private var title: Text {
        if let title = chapter.title, !hidesText {
            Text(verbatim: title)
        } else {
            Text("Chapter \(number)", comment: "Fallback chapter title; the number is its position in the video's chapter list.")
        }
    }

    private var imageHeight: CGFloat {
        max(44, metrics.contentHeight - metrics.castNameSize * 1.5 - metrics.captionSize * 1.5 - 20)
    }

    var body: some View {
        chapterButton
            .focused($focus, equals: .chapter(chapter.id))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(Text(verbatim: PlayerControls.timeLabel(chapter.start)))
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            .accessibilityIdentifier("player-chapter-\(number)")
    }

    @ViewBuilder
    private var chapterButton: some View {
        #if os(tvOS)
        Button(action: action) { content }
            .buttonStyle(.card)
        #else
        Button(action: action) { content }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(foreground)
        #endif
    }

    private var content: some View {
        Group {
            if metrics.isVertical {
                HStack(spacing: 12) {
                    thumbnail
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    caption
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail
                        .frame(width: imageHeight * 16 / 9, height: imageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    caption
                }
                .frame(width: imageHeight * 16 / 9, alignment: .leading)
            }
        }
        .padding(4)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(metrics.castNameFont)
                .lineLimit(1)
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
                Text(verbatim: PlayerControls.timeLabel(chapter.start))
                    .monospacedDigit()
            }
            .font(metrics.captionFont)
        }
        .foregroundStyle(foreground)
    }

    private var thumbnail: some View {
        FallbackAsyncImage(
            urls: hidesImage && spoilerSettings.mode == .placeholder ? [] : chapter.imageURL.map { [$0] } ?? [],
            variant: .landscapeCard,
            artworkPolicy: model.artworkPolicy
        ) {
            Image(systemName: "list.number")
                .font(metrics.titleFont)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .showingPlaceholderWhileLoading(true)
        .blur(radius: hidesImage && spoilerSettings.mode == .blur ? 28 : 0)
        .accessibilityHidden(true)
    }
}
#endif
