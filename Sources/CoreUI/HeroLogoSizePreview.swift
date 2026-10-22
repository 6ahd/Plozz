#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct HeroLogoSizePreview: View {
    let size: HeroLogoSize
    let surface: HeroLogoSizing.Surface
    let layout: HeroLogoSizing.Layout
    let cornerRadius: CGFloat

    public init(
        size: HeroLogoSize, surface: HeroLogoSizing.Surface, layout: HeroLogoSizing.Layout,
        cornerRadius: CGFloat = PlozzTheme.Metrics.Radius.content
    ) {
        self.size = size
        self.surface = surface
        self.layout = layout
        self.cornerRadius = cornerRadius
    }

    private var mobile: Bool { layout == .compact || layout == .regular }
    private var screen: CGSize {
        mobile ? CGSize(width: layout == .compact ? 390 : 820, height: 360)
            : CGSize(width: 1920, height: 1080)
    }

    public var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / screen.width
            scene
                .frame(width: screen.width, height: screen.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
        }
        .aspectRatio(screen.width / screen.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var scene: some View {
        let leading: CGFloat = mobile ? 22 : 144
        let wordmark = HeroLogoPreviewWordmark(
            size: size, layout: layout, availableWidth: mobile ? screen.width - leading * 2 : .infinity
        )
        let fitted = wordmark.fittedSize
        let baseline: CGFloat = mobile ? 205 : surface == .showcase ? 300 : 640
        let x = layout == .compact ? (screen.width - fitted.width) / 2 : leading
        return ZStack(alignment: .topLeading) {
            if mobile {
                Color(white: 0.06)
                HomePreviewArtwork()
                    .frame(width: screen.width * 0.75, height: screen.height)
                    .offset(x: screen.width * 0.25)
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, .black.opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                HomePreviewBackdrop(style: surface == .showcase ? .followsFocus : .carousel, size: screen)
            }
            wordmark
                .offset(x: x, y: baseline - fitted.height)
            VStack(alignment: .leading, spacing: mobile ? 10 : 22) {
                Capsule().fill(.white.opacity(0.5))
                    .frame(width: mobile ? 160 : 300, height: mobile ? 5 : 18)
                Capsule().fill(.white.opacity(0.3))
                    .frame(width: mobile ? 250 : 480, height: mobile ? 5 : 18)
                Capsule().fill(.white.opacity(0.3))
                    .frame(width: mobile ? 210 : 400, height: mobile ? 5 : 18)
                if surface != .showcase {
                    HStack(spacing: mobile ? 12 : 24) {
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: mobile ? 92 : 168, height: mobile ? 32 : 64)
                        Circle().fill(.white.opacity(0.25))
                            .frame(width: mobile ? 32 : 64, height: mobile ? 32 : 64)
                    }
                    .padding(.top, mobile ? 4 : 12)
                }
            }
            .offset(x: layout == .compact ? (screen.width - 250) / 2 : leading, y: baseline + (mobile ? 16 : 28))
            if !mobile {
                HStack(spacing: 32) {
                    ForEach(0..<5) { _ in
                        RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.14))
                            .frame(width: 360, height: 210)
                    }
                }
                .offset(x: leading, y: surface == .showcase ? 640 : 980)
            }
        }
    }
}

struct HeroLogoPreviewWordmark: View {
    let size: HeroLogoSize
    let layout: HeroLogoSizing.Layout
    var availableWidth: CGFloat = .infinity

    var fittedSize: CGSize {
        let box = HeroLogoSizing.box(for: layout, size: size, availableWidth: availableWidth)
        return HeroLogoFit.fittedSize(
            for: CGSize(width: 600, height: 110), maxWidth: box.width, maxHeight: box.height,
            coverage: 0.32, constrainsToBounds: layout.constrainsToBounds
        )
    }

    var body: some View {
        Text(verbatim: "NORTHSTAR")
            .font(.system(size: 82, weight: .black, design: .serif))
            .tracking(4)
            .foregroundStyle(.white)
            .fixedSize()
            .frame(width: 600, height: 110)
            .scaleEffect(fittedSize.width / 600, anchor: .topLeading)
            .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
    }
}
#endif
