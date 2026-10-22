#if canImport(SwiftUI)
import CoreModels
import MetadataKit
import SwiftUI

public enum FeaturedCardLayout {
    public static func size(viewportWidth: CGFloat, television: Bool) -> CGSize {
        let width = television
            ? min(560, max(280, (viewportWidth - 96) / 3.15))
            : min(440, max(220, viewportWidth - 48))
        return CGSize(width: width, height: width * (television ? 1.25 : 1.125))
    }
}

/// The editor and the live rail share the same artwork, title and metadata.
public struct FeaturedCardArtwork<Video: View>: View {
    private let item: MediaItem
    private let size: CGSize
    private let spoilerSettings: SpoilerSettings
    private let video: Video
    @Environment(\.plozzArtworkPolicy) private var artworkPolicy
    @Environment(\.plozzNativeFocusSurface) private var nativeFocusSurface

    public init(
        item: MediaItem, size: CGSize, spoilerSettings: SpoilerSettings = .default,
        @ViewBuilder video: () -> Video
    ) {
        self.item = item
        self.size = size
        self.spoilerSettings = spoilerSettings
        self.video = video()
    }

    private var title: Text {
        spoilerSettings.shouldHideText(for: item)
            ? Text(spoilerSettings.maskedTitle(for: item)) : Text(verbatim: item.title)
    }

    private var metadata: String {
        [item.genres.first, item.productionYear.map(String.init), item.officialRating]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            FallbackAsyncImage(
                references: spoilerSettings.shouldHideThumbnail(for: item)
                    ? item.seriesArtworkReferences() : item.artworkReferences(for: .homeHero),
                variant: .posterCard,
                previewVariant: .posterPreview,
                artworkPolicy: artworkPolicy.forPlacement(.homeHero),
                asyncFallbackURL: { [item, spoilerSettings] in
                    guard !spoilerSettings.shouldHideThumbnail(for: item) else { return nil }
                    return await ArtworkSession.resolveArtwork(background: false) {
                        await ArtworkRouter.shared.portraitHeroArtworkURL(for: item)
                    }
                },
                pinIdentity: "\(item.stablePresentationID)|featured"
            ) {
                MediaArtworkPlaceholder(tint: .white, glyphSize: size.width * 0.12)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            video
                .frame(width: size.width, height: size.height)
                .clipped()
                .accessibilityHidden(true)
            LinearGradient(
                stops: [.init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.42), location: 0.65),
                        .init(color: .black.opacity(0.88), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 12) {
                HeroLogoArtwork(
                    references: item.artworkReferences(for: .logo),
                    asyncFallbackURL: HeroLogoFallback(for: item) { [item] in
                        await ArtworkSession.resolveArtwork(background: false) {
                            await ArtworkRouter.shared.artworkURL(.logo, for: item)
                        }
                    },
                    maxWidth: size.width * 0.72, maxHeight: size.height * 0.19,
                    constrainsToBounds: true
                ) {
                    title.font(.title2.bold()).lineLimit(3).foregroundStyle(.white)
                }
                if !metadata.isEmpty {
                    Text(verbatim: metadata)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            .padding(size.width * 0.065)
        }
        .frame(width: size.width, height: size.height)
        .background(.black)
        // TVCardView owns the outer rounding; a second curve exposes its backing.
        .clipShape(RoundedRectangle(cornerRadius: nativeFocusSurface ? 0 : 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: metadata))
    }
}

public extension FeaturedCardArtwork where Video == EmptyView {
    init(item: MediaItem, size: CGSize, spoilerSettings: SpoilerSettings = .default) {
        self.init(item: item, size: size, spoilerSettings: spoilerSettings) { EmptyView() }
    }
}
#endif
