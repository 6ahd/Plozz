#if canImport(UIKit)
import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import CoreUI

@MainActor
final class ExtendedArtworkBitmapTests: XCTestCase {
    func testContinueWatchingPreviewsToggleOnlyTheirCaptionPixels() throws {
        for style in ContinueWatchingArtworkStyle.allCases {
            for details in ContinueWatchingPlaybackDetails.allCases {
                for scheme in [ColorScheme.light, .dark] {
                    for size in [CGSize(width: 96, height: 112), CGSize(width: 240, height: 200)] {
                        let images = try [false, true].map { captions in
                            let renderer = ImageRenderer(content:
                                ContinueWatchingArtworkSwatch(
                                    style: style, playbackDetails: details, showsCaptions: captions
                                )
                                .frame(width: size.width, height: size.height)
                                .environment(\.colorScheme, scheme)
                                .background(scheme == .dark ? Color.black : .white)
                            )
                            renderer.scale = 1
                            return try pixels(XCTUnwrap(renderer.uiImage))
                        }
                        let changed = stride(from: 0, to: images[0].count, by: 4).filter {
                            images[0][$0..<($0 + 3)] != images[1][$0..<($0 + 3)]
                        }
                        XCTAssertGreaterThan(changed.count, 30, "\(style) / \(details) must show caption lines.")
                        XCTAssertTrue(changed.allSatisfy { index in
                            images.allSatisfy { image in
                                abs(Int(image[index]) - Int(image[index + 1])) <= 1
                                    && abs(Int(image[index]) - Int(image[index + 2])) <= 1
                            }
                        }, "Only neutral caption pixels may change; the colored artwork must stay in place.")
                    }
                }
            }
        }
    }

    func testSharedCardProgressRendersAtTheUnchangedDetailedHeight() throws {
        let item = MediaItem(id: "progress", title: "Movie", kind: .movie, runtime: 3600, resumePosition: 1800)
        for metrics in [PlozzMetrics.standard, .touch(density: .standard)] {
            let renderer = ImageRenderer(content:
                MediaCardPlaybackIndicators(
                    item: item, hidesStatus: true, badgeInset: 0,
                    progressHeight: metrics.progressBarHeight, progressBottomInset: 20
                )
                .environment(\.plozzMetrics, metrics)
                .plozzChromeFocused(true)
                .frame(width: 200, height: 100)
                .background(.black)
            )
            renderer.scale = 1
            let rgba = try pixels(XCTUnwrap(renderer.uiImage))
            let brightRows = (0..<100).filter { row in
                (0..<3).allSatisfy { rgba[(row * 200 + 50) * 4 + $0] > 150 }
            }
            XCTAssertEqual(brightRows.count, Int(metrics.resumeChipBarHeight))
        }
    }

    func testPortraitResumeChromeKeepsTheLandscapeBottomInset() throws {
        let item = MediaItem(id: "resume", title: "Movie", kind: .movie, runtime: 3600, resumePosition: 900)
        for metrics in [PlozzMetrics.standard, .touch(density: .standard)] {
            var bottomInsets: [Int] = []
            for portrait in [false, true] {
                let height: CGFloat = portrait ? 660 : 300
                let renderer = ImageRenderer(content:
                    ResumeChipOverlay(item: item, compactHorizontalLayout: portrait)
                        .environment(\.plozzMetrics, metrics)
                        .frame(width: 400, height: height)
                        .background(.black)
                )
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let rgba = try pixels(image)
                let lastBrightPixel = try XCTUnwrap(stride(from: 0, to: rgba.count, by: 4).filter {
                    rgba[$0] > 150 && rgba[$0 + 1] > 150 && rgba[$0 + 2] > 150
                }.last)
                bottomInsets.append(Int(height) - 1 - lastBrightPixel / (400 * 4))
            }
            XCTAssertEqual(bottomInsets[0], bottomInsets[1],
                           "Shortening the reflection must not move the playback controls relative to the bottom.")
        }
    }

    func testPortraitBitmapPreservesPosterPixelsAboveItsReflectedExtension() throws {
        let source = fixture(size: CGSize(width: 200, height: 300))
        let size = CGSize(width: 200, height: (200 / ContinueWatchingCardShape.portraitAspectRatio).rounded())
        let actual = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0,
            progressivelyBlursReflection: true
        ))
        let original = try pixels(source)
        let rendered = try pixels(actual)
        let pictureBytes = 200 * 296 * 4
        let error = zip(original.prefix(pictureBytes), rendered.prefix(pictureBytes)).reduce(0.0) {
            $0 + abs(Double($1.0) - Double($1.1))
        } / Double(pictureBytes)
        XCTAssertLessThanOrEqual(error, 0.8, "The poster, including its footer, must not be cropped or darkened.")
        XCTAssertEqual(actual.size.height, size.height, accuracy: 1)
        XCTAssertGreaterThan(rendered.count, original.count)

        let reference = ImageRenderer(content:
            ExtendedArtworkFill(
                image: Image(uiImage: source), artworkAspectRatio: 2.0 / 3.0, sideCrop: 0,
                progressivelyBlursReflection: true
            )
                .frame(width: size.width, height: size.height).clipped()
        )
        reference.scale = 1
        reference.isOpaque = true
        let referencePixels = try pixels(XCTUnwrap(reference.uiImage))
        XCTAssertEqual(rendered.count, referencePixels.count)
        let differences = zip(rendered, referencePixels).map { abs(Int($0) - Int($1)) }
        XCTAssertLessThanOrEqual(try XCTUnwrap(differences.prefix(pictureBytes).max()), 1,
                                "The sharp poster must remain identical across renderers.")
        let reflectionDifferences = differences.dropFirst(200 * 300 * 4)
        let reflectionMean = Double(reflectionDifferences.reduce(0, +)) / Double(reflectionDifferences.count)
        if reflectionMean > 0.8 {
            for (name, image) in [("native-reflection", actual), ("swiftui-reflection", try XCTUnwrap(reference.uiImage))] {
                let attachment = XCTAttachment(image: image)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        // Blurred pixels vary slightly between the CGContext and UIImage paths.
        // Apply the existing bitmap mean-error budget to the reflection alone.
        XCTAssertLessThanOrEqual(reflectionMean, 0.8)
    }

    func testReflectionLosesDetailGraduallyInsteadOfBlurringTheOriginalPoster() throws {
        let source = fixture(size: CGSize(width: 200, height: 300))
        let size = CGSize(width: 200, height: (200 / ContinueWatchingCardShape.portraitAspectRatio).rounded())
        let sharp = try pixels(XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0
        )))
        let soft = try pixels(XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0,
            progressivelyBlursReflection: true
        )))
        XCTAssertEqual(Array(soft.prefix(200 * 296 * 4)), Array(sharp.prefix(200 * 296 * 4)))
        func edge(_ data: [UInt8], row: Int) -> Double {
            Double((50..<110).map { x in
                abs(Int(data[(row * 200 + x + 1) * 4]) - Int(data[(row * 200 + x) * 4]))
            }.max() ?? 0)
        }
        let ratios = [301, 312, 326].map { edge(soft, row: $0) / max(1, edge(sharp, row: $0)) }
        XCTAssertGreaterThan(ratios[0], 0.8, "The join should start clear: \(ratios)")
        XCTAssertLessThan(ratios[1], ratios[0] * 0.8, "The middle should be softer: \(ratios)")
        XCTAssertLessThan(ratios[2], ratios[1] * 0.6, "The bottom should be softest: \(ratios)")
    }

    func testBitmapCacheSeparatesArtworkAspectAndCrop() throws {
        let source = fixture(size: CGSize(width: 200, height: 300))
        let size = CGSize(width: 200, height: 360)
        let portrait = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0
        ))
        let repeated = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0
        ))
        let differentAspect = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 16.0 / 9.0, sideCrop: 0
        ))
        let differentCrop = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0.1
        ))
        XCTAssertTrue(portrait === repeated)
        XCTAssertFalse(portrait === differentAspect)
        XCTAssertFalse(portrait === differentCrop)
        let blurred = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: size, scale: 1, artworkAspectRatio: 2.0 / 3.0, sideCrop: 0,
            progressivelyBlursReflection: true
        ))
        XCTAssertFalse(portrait === blurred, "Reduced-effects and blurred reflections must not share cached pixels.")
    }

    func testRecreatedCardsReuseThePreparedBitmap() throws {
        let source = fixture(size: CGSize(width: 640, height: 360))
        let size = CGSize(width: 320, height: 230)
        let first = try XCTUnwrap(ExtendedArtworkBitmap.render(image: source, size: size, scale: 1))
        let reused = try XCTUnwrap(ExtendedArtworkBitmap.render(image: source, size: size, scale: 1))
        XCTAssertTrue(first === reused)
    }

    func testBitmapReuseIsScopedToSourceSizeAndScale() throws {
        let source = fixture(size: CGSize(width: 640, height: 360))
        let size = CGSize(width: 320, height: 230)
        let first = try XCTUnwrap(ExtendedArtworkBitmap.render(image: source, size: size, scale: 1))
        let otherSource = fixture(size: CGSize(width: 360, height: 640))
        let changedSource = try XCTUnwrap(ExtendedArtworkBitmap.render(image: otherSource, size: size, scale: 1))
        let changedSize = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: source, size: CGSize(width: 400, height: 280), scale: 1
        ))
        let changedScale = try XCTUnwrap(ExtendedArtworkBitmap.render(image: source, size: size, scale: 2))
        XCTAssertFalse(first === changedSource)
        XCTAssertFalse(first === changedSize)
        XCTAssertFalse(first === changedScale)
        XCTAssertEqual(changedSize.size, CGSize(width: 400, height: 280))
        XCTAssertEqual(changedScale.scale, 2)
        XCTAssertEqual(changedScale.cgImage?.width, 640)
    }

    func testReusingRendererDoesNotChangeAPreviouslyReturnedBitmap() throws {
        let first = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: fixture(size: CGSize(width: 640, height: 360)),
            size: CGSize(width: 320, height: 230), scale: 1
        ))
        let expected = try pixels(first)
        _ = try XCTUnwrap(ExtendedArtworkBitmap.render(
            image: fixture(size: CGSize(width: 360, height: 640)),
            size: CGSize(width: 400, height: 280), scale: 2
        ))
        XCTAssertEqual(try pixels(first), expected)
    }

    func testBitmapMatchesTheExistingReflectionAndCrop() throws {
        for sourceSize in [CGSize(width: 640, height: 360), CGSize(width: 360, height: 640), CGSize(width: 640, height: 320)] {
            let source = fixture(size: sourceSize)
            for size in [CGSize(width: 320, height: 180), CGSize(width: 320, height: 230)] {
                for scale in [CGFloat(1), 2] {
                    let reference = ImageRenderer(content:
                        ExtendedArtworkFill(image: Image(uiImage: source))
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    )
                    reference.scale = scale
                    reference.isOpaque = true
                    let expected = try XCTUnwrap(reference.uiImage)
                    let actual = try XCTUnwrap(ExtendedArtworkBitmap.render(image: source, size: size, scale: scale))
                    XCTAssertEqual(actual.size, expected.size)
                    let expectedPixels = try pixels(expected)
                    let actualPixels = try pixels(actual)
                    XCTAssertEqual(actualPixels.count, expectedPixels.count)
                    guard actualPixels.count == expectedPixels.count else { continue }
                    let error = zip(actualPixels, expectedPixels).reduce(0.0) {
                        $0 + abs(Double($1.0) - Double($1.1))
                    } / Double(actualPixels.count)
                    XCTAssertLessThanOrEqual(error, 0.8, "source=\(sourceSize) target=\(size) scale=\(scale)")
                }
            }
        }
    }

    private func fixture(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            for index in 0..<24 {
                UIColor(
                    red: CGFloat(index) / 24, green: CGFloat(23 - index) / 24,
                    blue: 0.4, alpha: 1
                ).setFill()
                renderer.fill(CGRect(x: 0, y: CGFloat(index) * size.height / 24,
                                     width: size.width, height: size.height / 24))
            }
            UIColor.blue.setFill()
            renderer.fill(CGRect(x: size.width * 0.35, y: 0,
                                 width: size.width * 0.1, height: size.height))
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try result.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }
}
#endif
