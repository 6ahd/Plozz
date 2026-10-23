#if canImport(SwiftUI)
import CoreModels
import MetadataKit
import SwiftUI

public enum FeaturedCardLayout {
    public static func size(viewportWidth: CGFloat, television: Bool) -> CGSize {
        let width = television
            ? min(560, max(280, (viewportWidth - 96) / 3.15))
            : min(440, max(220, viewportWidth - 48))
        guard television else { return CGSize(width: width, height: width * 1.125) }
        // Preserve the 4:5 ratio without fractional native clip bounds, even on 2x displays.
        let alignedWidth = (width / 4).rounded(.up) * 4
        return CGSize(width: alignedWidth, height: alignedWidth * 1.25)
    }
}

/// The editor and the live rail share the same artwork, title and metadata.
public struct FeaturedCardArtwork<Video: View>: View {
    private let item: MediaItem
    private let size: CGSize
    private let spoilerSettings: SpoilerSettings
    private let usesNativeClipping: Bool
    private let video: Video
    @Environment(\.plozzArtworkPolicy) private var artworkPolicy
    @Environment(\.plozzNativeFocusSurface) private var nativeFocusSurface
    #if os(tvOS)
    private struct NativeControl {
        let focus: PlozzCardFocus.Binding
        let action: () -> Void
    }
    private var nativeControl: NativeControl?

    public func nativeButton(focus: PlozzCardFocus.Binding, action: @escaping () -> Void) -> Self {
        var copy = self
        copy.nativeControl = NativeControl(focus: focus, action: action)
        return copy
    }
    #endif

    public init(
        item: MediaItem, size: CGSize, spoilerSettings: SpoilerSettings = .default,
        usesNativeClipping: Bool = false,
        @ViewBuilder video: () -> Video
    ) {
        self.item = item
        self.size = size
        self.spoilerSettings = spoilerSettings
        self.usesNativeClipping = usesNativeClipping
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
        #if os(tvOS)
        if let nativeControl {
            nativeButton(control: nativeControl)
        } else {
            standaloneArtwork
        }
        #else
        standaloneArtwork
        #endif
    }

    private var standaloneArtwork: some View {
        Group {
            if usesNativeClipping || nativeFocusSurface {
                layers { artwork }
            } else {
                layers { artwork }.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: metadata))
    }

    private var artwork: FallbackAsyncImage<ArtworkFillImage, MediaArtworkPlaceholder> {
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
            placeholder
        }
    }

    private var placeholder: MediaArtworkPlaceholder {
        MediaArtworkPlaceholder(tint: .white, glyphSize: size.width * 0.12)
    }

    #if os(tvOS)
    private func nativeButton(control: NativeControl) -> some View {
        artwork.resolvedBitmap { image in
            NativeTVPoster(
                image: image, treatment: .original, aspectRatio: size.width / size.height,
                fallbackWidth: size.width,
                title: spoilerSettings.shouldHideText(for: item)
                    ? .localized(spoilerSettings.maskedTitle(for: item)) : .content(item.title),
                subtitle: metadata,
                overlay: layers {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                },
                rasterizesOverlay: false,
                focus: control.focus, action: control.action
            )
            .focused(control.focus.focusState)
            .frame(width: size.width, height: size.height)
        }
    }
    #endif

    private func layers<Artwork: View>(@ViewBuilder artwork: () -> Artwork) -> some View {
        ZStack(alignment: .bottomLeading) {
            artwork()
                .frame(width: size.width, height: size.height)
            video
                .frame(width: size.width, height: size.height)
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
    }
}

public extension FeaturedCardArtwork where Video == EmptyView {
    init(
        item: MediaItem, size: CGSize, spoilerSettings: SpoilerSettings = .default,
        usesNativeClipping: Bool = false
    ) {
        self.init(
            item: item, size: size, spoilerSettings: spoilerSettings, usesNativeClipping: usesNativeClipping
        ) { EmptyView() }
    }
}
#endif
