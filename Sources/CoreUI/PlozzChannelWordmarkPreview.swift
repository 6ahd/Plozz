#if DEBUG && canImport(SwiftUI)
import SwiftUI

struct PlozzChannelWordmarkPreview: View {
    enum Style: String {
        case quietSignature = "quiet-signature"
        case mascotFirst = "mascot-first"
    }

    static let requestedStyle = ProcessInfo.processInfo.environment["PLOZZ_CHANNEL_BADGE_PREVIEW"]
        .flatMap(Style.init(rawValue:))

    let name: String
    let size: CGSize
    let cornerRadius: CGFloat
    let style: Style
    @Environment(\.colorSchemeContrast) private var contrast

    private let ink = Color(red: 244 / 255, green: 246 / 255, blue: 248 / 255)
    private let signatureInk = Color(red: 228 / 255, green: 233 / 255, blue: 237 / 255)
    private var scale: CGFloat { size.height / 128 }
    private var field: Color {
        style == .quietSignature
            ? Color(red: 25 / 255, green: 35 / 255, blue: 43 / 255)
            : Color(red: 21 / 255, green: 33 / 255, blue: 41 / 255)
    }

    var body: some View {
        Group {
            switch style {
            case .quietSignature:
                VStack(alignment: .leading, spacing: 8 * scale) {
                    HStack(spacing: 5 * scale) {
                        mascot.frame(width: 28 * scale, height: 28 * scale)
                        Text(verbatim: "plozz")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .tracking(0.25 * scale)
                    }
                    .foregroundStyle(signatureInk)
                    Spacer(minLength: 0)
                    title(size: 26 * scale, alignment: .leading)
                }
                .padding(.horizontal, size.width * 0.09)
                .padding(.vertical, 17 * scale)
            case .mascotFirst:
                VStack(spacing: 10 * scale) {
                    mascot
                        .foregroundStyle(signatureInk)
                        .frame(width: 40 * scale, height: 40 * scale)
                    title(size: 23 * scale, alignment: .center)
                }
                .padding(12 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(ink)
        .frame(width: size.width, height: size.height)
        .background(field)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    ink.opacity(contrast == .increased ? 0.4 : 0.14),
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .accessibilityHidden(true)
    }

    private var mascot: some View {
        PlozzChannelPixelMascot().fill(style: FillStyle(eoFill: true))
    }

    private func title(size fontSize: CGFloat, alignment: TextAlignment) -> some View {
        Text(name)
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(-0.65 * scale)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

private struct PlozzChannelPixelMascot: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outlines: [[CGPoint]] = [
            [
                .init(x: 6, y: 6), .init(x: 26, y: 6), .init(x: 26, y: 7), .init(x: 28, y: 7),
                .init(x: 28, y: 8), .init(x: 29, y: 8), .init(x: 29, y: 10), .init(x: 30, y: 10),
                .init(x: 30, y: 26), .init(x: 29, y: 26), .init(x: 29, y: 28), .init(x: 28, y: 28),
                .init(x: 28, y: 29), .init(x: 26, y: 29), .init(x: 26, y: 30), .init(x: 6, y: 30),
                .init(x: 6, y: 29), .init(x: 4, y: 29), .init(x: 4, y: 28), .init(x: 3, y: 28),
                .init(x: 3, y: 26), .init(x: 2, y: 26), .init(x: 2, y: 10), .init(x: 3, y: 10),
                .init(x: 3, y: 8), .init(x: 4, y: 8), .init(x: 4, y: 7), .init(x: 6, y: 7)
            ],
            [
                .init(x: 6, y: 8), .init(x: 26, y: 8), .init(x: 26, y: 9), .init(x: 27, y: 9),
                .init(x: 27, y: 10), .init(x: 28, y: 10), .init(x: 28, y: 26), .init(x: 27, y: 26),
                .init(x: 27, y: 27), .init(x: 26, y: 27), .init(x: 26, y: 28), .init(x: 6, y: 28),
                .init(x: 6, y: 27), .init(x: 5, y: 27), .init(x: 5, y: 26), .init(x: 4, y: 26),
                .init(x: 4, y: 10), .init(x: 5, y: 10), .init(x: 5, y: 9), .init(x: 6, y: 9)
            ],
            [
                .init(x: 9, y: 2), .init(x: 11, y: 2), .init(x: 11, y: 3), .init(x: 12, y: 3),
                .init(x: 12, y: 4), .init(x: 13, y: 4), .init(x: 13, y: 5), .init(x: 14, y: 5),
                .init(x: 14, y: 4), .init(x: 15, y: 4), .init(x: 15, y: 3), .init(x: 16, y: 3),
                .init(x: 16, y: 2), .init(x: 18, y: 2), .init(x: 18, y: 4), .init(x: 17, y: 4),
                .init(x: 17, y: 5), .init(x: 16, y: 5), .init(x: 16, y: 6), .init(x: 11, y: 6),
                .init(x: 11, y: 5), .init(x: 10, y: 5), .init(x: 10, y: 4), .init(x: 9, y: 4)
            ]
        ]
        for points in outlines {
            path.addLines(points)
            path.closeSubpath()
        }
        for eyeX: CGFloat in [12, 17] {
            path.addRect(CGRect(x: eyeX, y: 14, width: 3, height: 1))
            path.addRect(CGRect(x: eyeX + 1, y: 15, width: 2, height: 1))
            path.addRect(CGRect(x: eyeX, y: 16, width: 2, height: 1))
            path.addRect(CGRect(x: eyeX, y: 17, width: 3, height: 1))
        }
        path.addRect(CGRect(x: 13, y: 20, width: 1, height: 1))
        path.addRect(CGRect(x: 18, y: 20, width: 1, height: 1))
        path.addRect(CGRect(x: 14, y: 21, width: 4, height: 1))
        let scale = min(rect.width, rect.height) / 32
        return path.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 16 * scale, ty: rect.midY - 16 * scale
        ))
    }
}
#endif
