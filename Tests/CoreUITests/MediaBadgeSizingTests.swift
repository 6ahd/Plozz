#if canImport(UIKit)
import CoreModels
@testable import CoreUI
import CoreText
import SwiftUI
import UIKit
import XCTest

@MainActor
final class MediaBadgeSizingTests: XCTestCase {
    private let badges: [MediaBadge] = [
        MediaBadge("4K", style: .prominent),
        MediaBadge("Dolby Vision", style: .dolby),
        MediaBadge("Dolby Atmos", style: .dolby),
        MediaBadge("HDR10", style: .hdr),
        MediaBadge("HDR10+", style: .hdr),
        MediaBadge("SDR", style: .sdr),
        MediaBadge("DTS-HD", style: .dts, detail: "5.1"),
        MediaBadge("Dolby TrueHD", style: .dolby, detail: "7.1"),
        MediaBadge("DTS:X", style: .dts),
        MediaBadge("5.1", style: .audio),
        MediaBadge("1080p", style: .prominent)
    ]

    private func size(of view: some View) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(
            in: CGSize(width: 2_000, height: 500)
        )
    }

    private var metadataScale: CGFloat {
        #if os(iOS)
        0.6
        #else
        0.75
        #endif
    }

    func testMetadataBadgesUsePlatformCompactScale() {
        for badge in badges {
            let original = size(of: MediaBadgeChip(badge: badge)
                .environment(\.dynamicTypeSize, .large))
            let compact = size(of: MetadataMediaBadgeChip(badge: badge)
                .environment(\.dynamicTypeSize, .large))
            let expected = size(of: MediaBadgeChip(badge: badge)
                .environment(\.mediaBadgeScale, metadataScale)
                .environment(\.dynamicTypeSize, .large))
            XCTAssertEqual(compact.width, expected.width, accuracy: 0.5, badge.label)
            // Small system fonts use optical spacing, not a linear transform of larger glyphs.
            XCTAssertLessThan(compact.width, original.width, badge.label)
            XCTAssertEqual(compact.height, original.height * metadataScale, accuracy: 1, badge.label)
        }
    }

    func testMetadataBadgesPreserveTheContainerScale() {
        let badge = MediaBadge("4K", style: .prominent)
        let reduced = size(of: MetadataMediaBadgeChip(badge: badge)
            .environment(\.mediaBadgeScale, 0.8)
            .environment(\.dynamicTypeSize, .large))
        let expected = size(of: MediaBadgeChip(badge: badge)
            .environment(\.mediaBadgeScale, 0.8 * metadataScale)
            .environment(\.dynamicTypeSize, .large))
        XCTAssertEqual(reduced.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(reduced.height, expected.height, accuracy: 0.5)
    }

    func testPorcelainUsesTheBundledVariableFontAtThePreviewWeights() {
        for weight: CGFloat in [450, 600, 650] {
            let font = PorcelainBadgeFont.uiFont(size: 15, weight: weight)
            XCTAssertTrue(font.familyName.hasPrefix("Outfit"), font.familyName)
            let variation = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
            XCTAssertEqual(variation?[NSNumber(value: 0x77676874)]?.doubleValue, Double(weight))
        }
    }

    func testTechnicalBadgesShareHeightAndKeepChannelsInsideTheBadge() {
        for badge in badges {
            XCTAssertEqual(size(of: MediaBadgeChip(badge: badge)).height, 30, accuracy: 0.5, badge.label)
        }
        let plain = size(of: MediaBadgeChip(badge: MediaBadge("Dolby TrueHD", style: .dolby)))
        let channels = size(of: MediaBadgeChip(badge: MediaBadge("Dolby TrueHD", style: .dolby, detail: "7.1")))
        XCTAssertGreaterThan(channels.width, plain.width + 20)
        XCTAssertEqual(channels.height, plain.height, accuracy: 0.5)
    }

    func testPorcelainAndFamilyBadgeRenderInBothThemes() throws {
        for palette in [ThemePalette.light, .dark, .pureBlack] {
            let content = VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    FamilyGuidanceAgeBadge(age: 14)
                    MediaBadgeChip(badge: MediaBadge("PG-13", style: .rating))
                }
                MediaBadgeRow(badges: badges)
                    .frame(width: 900)
            }
            .padding(24)
            .background(palette.backgroundBase)
            .environment(\.themePalette, palette)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "porcelain-family-\(palette.isLight ? "light" : "dark")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testFamilySymbolHasClearanceInsideTheUnchangedBadgeFrame() throws {
        #if os(iOS)
        let iconSlot = 20
        #else
        let iconSlot = 28
        #endif
        let renderer = ImageRenderer(content: FamilyGuidanceAgeBadge(age: 14)
            .environment(\.themePalette, .dark)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        XCTAssertEqual(Double(image.height), Double(iconSlot + 8), accuracy: 1)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let symbolRows = (0..<image.height).filter { y in
            (9..<(9 + iconSlot)).contains { x in
                pixels[(y * image.width + x) * 4 + 3] > 200
            }
        }
        let firstRow = try XCTUnwrap(symbolRows.first)
        let lastRow = try XCTUnwrap(symbolRows.last)
        XCTAssertLessThanOrEqual(lastRow - firstRow + 1, Int(ceil(Double(iconSlot) * 0.8)))
        XCTAssertGreaterThanOrEqual(firstRow, 6)
        XCTAssertGreaterThanOrEqual(image.height - lastRow - 1, 6)
    }

    func testFormatAndChannelOrderDoesNotReverseInRTL() throws {
        for badge in [
            MediaBadge("Dolby Vision", style: .dolby),
            MediaBadge("Dolby TrueHD", style: .dolby, detail: "7.1")
        ] {
            func render(_ direction: LayoutDirection) throws -> Data {
                let renderer = ImageRenderer(content:
                    MediaBadgeChip(badge: badge)
                        .environment(\.layoutDirection, direction)
                        .environment(\.themePalette, .dark)
                )
                renderer.scale = 2
                return try XCTUnwrap(renderer.uiImage?.pngData())
            }
            XCTAssertEqual(try render(.leftToRight), try render(.rightToLeft), badge.label)
        }
    }

    #if os(iOS)
    func testResolutionAndDolbyMarksAreComparableToMetadataTextHeight() {
        let textHeight = size(of: Text("2025")
            .font(.subheadline)
            .environment(\.dynamicTypeSize, .large)).height
        for badge in badges.prefix(3) {
            let badgeHeight = size(of: MetadataMediaBadgeChip(badge: badge)
                .environment(\.dynamicTypeSize, .large)).height
            XCTAssertGreaterThanOrEqual(badgeHeight, textHeight * 0.85, badge.label)
            XCTAssertLessThanOrEqual(badgeHeight, textHeight * 1.2, badge.label)
        }
    }

    func testBadgeHeightTracksTheMetadataTextSize() {
        let badge = MediaBadge("4K", style: .prominent)
        let normalHeight = size(of: MetadataMediaBadgeChip(badge: badge)
            .environment(\.dynamicTypeSize, .large)).height
        let normalTextHeight = size(of: Text("2025")
            .font(.subheadline)
            .environment(\.dynamicTypeSize, .large)).height
        for category in [DynamicTypeSize.xSmall, .xxxLarge, .accessibility3] {
            let badgeHeight = size(of: MetadataMediaBadgeChip(badge: badge)
                .environment(\.dynamicTypeSize, category)).height
            let textHeight = size(of: Text("2025")
                .font(.subheadline)
                .environment(\.dynamicTypeSize, category)).height
            XCTAssertEqual(
                badgeHeight / normalHeight,
                textHeight / normalTextHeight,
                accuracy: 0.08,
                "\(category)"
            )
        }
    }
    #endif

    func testMetadataRowRendersCompactBadgesInBothThemes() throws {
        for scheme in [ColorScheme.light, .dark] {
            let row = HStack(spacing: 12) {
                Text("2025 \u{00B7} 56m")
                    .font(.subheadline.weight(.medium))
                Label("8.3", systemImage: "star.fill")
                    .font(.subheadline.weight(.medium))
                ForEach(Array(badges.prefix(4))) { badge in
                    MetadataMediaBadgeChip(badge: badge)
                }
            }
            .fixedSize()
            .padding(16)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.themePalette, scheme == .dark ? .dark : .light)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, .large)
            let renderer = ImageRenderer(content: row)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = "compact-metadata-badges-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
#endif
