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
                    LazyVStack(spacing: 8) { chapters }
                } else {
                    LazyHStack(spacing: metrics.columnSpacing) { chapters }
                        .frame(height: metrics.cardHeight)
                        .padding(.trailing, metrics.contentPadding)
                }
            }
            .scrollClipDisabled(!metrics.isVertical)
            // Rows retain their opening inset; wide cards fill the stage like Cast.
            .padding(.vertical, metrics.isVertical ? metrics.contentPadding : 0)
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

    private var cardWidth: CGFloat {
        let imageHeight = max(44, metrics.cardHeight - metrics.castVerticalInset * 2
            - metrics.castNameSize * 1.5 - metrics.captionSize * 1.5 - 16)
        return imageHeight * 16 / 9 + 24
    }

    private var contentInset: CGFloat {
        max(metrics.contentPadding, metrics.panelCornerRadius * 2 / 3)
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

    private var chapterButton: some View {
        Button(action: action) { content }
            .buttonStyle(PlayerOverVideoCardStyle(
                focused: focus == .chapter(chapter.id),
                cornerRadius: metrics.panelCornerRadius - (metrics.isVertical ? 6 : 0),
                focusScale: metrics.isVertical ? 1 : 1.10,
                pressScale: metrics.isVertical ? 0.98 : 1,
                mediaGlass: true
            ))
    }

    @ViewBuilder
    private var content: some View {
        if metrics.isVertical {
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: metrics.castHeadshot * 16 / 9, height: metrics.castHeadshot)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                caption
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: metrics.castRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail
                    .frame(width: cardWidth - contentInset * 2,
                           height: (cardWidth - contentInset * 2) * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                caption
            }
            .padding(contentInset)
            .frame(width: cardWidth, height: metrics.cardHeight, alignment: .bottom)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(metrics.castNameFont)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(verbatim: PlayerControls.timeLabel(chapter.start))
                    .monospacedDigit()
                Image(systemName: "play.fill")
                    .opacity(isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .font(metrics.captionFont)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
