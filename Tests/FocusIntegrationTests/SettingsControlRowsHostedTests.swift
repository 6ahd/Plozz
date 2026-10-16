import CoreUI
@testable import FeatureSettings
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsControlRowsHostedTests: XCTestCase {
    func testStandaloneNavigationFocusMatchesTheIdleContainerSilhouette() throws {
        let focused = ImageRenderer(content:
            SettingsFocusRow(isFocused: true, size: .navigation) {
                Color.clear.frame(width: 320, height: 80)
            }
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        )
        let idle = ImageRenderer(content:
            RoundedRectangle(cornerRadius: SettingsRowMetrics.navigationCornerRadius, style: .continuous)
                .fill(Color.white)
                .frame(width: 320, height: 80)
                .background(Color.black)
        )
        focused.scale = 1
        idle.scale = 1
        let focusedPixels = try pixels(XCTUnwrap(focused.cgImage))
        let idlePixels = try pixels(XCTUnwrap(idle.cgImage))
        XCTAssertEqual(focusedPixels.map { $0 > 128 }, idlePixels.map { $0 > 128 },
                       "Focus must not tighten the standalone card's rounded outline.")
    }

    func testSeparatorsFollowTheWholeRowAndNeverTheLastVisibleItem() throws {
        for count in [3, 1, 2, 0] {
            let renderer = ImageRenderer(content:
                SettingsControlRows {
                    ForEach(0..<count, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            Color.red.frame(width: 100, height: 40)
                            if index == 0 {
                                // A helper belongs to the first row, not to a new row.
                                Color.green.frame(width: 100, height: 40)
                            }
                        }
                    }
                }
                .frame(width: 320, height: 240, alignment: .topLeading)
                .background(Color.black)
                .environment(\.themePalette, .dark)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let bytes = try pixels(image)
            let lineRows = (0..<image.height).filter { y in
                let offset = (y * image.width + 280) * 4
                return bytes[offset] > 0 || bytes[offset + 1] > 0 || bytes[offset + 2] > 0
            }
            let expected = count < 2 ? [] : Array([88, 145].prefix(count - 1))
            XCTAssertEqual(lineRows, expected,
                           "\(count) rows: separate only adjacent controls, after the first row's helper.")
        }
    }

    func testFocusFillLeavesEightPointsOnEitherSideOfTheDivider() throws {
        for focused in 0..<3 {
            let renderer = ImageRenderer(content:
                SettingsControlRows {
                    ForEach(0..<3) { index in
                        SettingsFocusRow(isFocused: index == focused) {
                            Color.clear.frame(width: 320, height: 40)
                        }
                    }
                }
                .frame(width: 320, height: 200, alignment: .topLeading)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
                .environment(\.themePalette, .dark)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let bytes = try pixels(image)
            let whiteRows = (0..<image.height).filter { bytes[($0 * image.width + 160) * 4] > 240 }
            let top = focused * 57
            XCTAssertEqual(whiteRows, Array(top..<(top + 40)),
                           "The focus fill must not bleed into the shared 8pt divider clearance.")
            for dividerY in [48, 105] {
                XCTAssertGreaterThan(bytes[(dividerY * image.width + 160) * 4], 0)
                for y in (dividerY - 8)...(dividerY + 8) where y != dividerY {
                    XCTAssertEqual(bytes[(y * image.width + 160) * 4], 0)
                }
            }
        }
    }

    func testCategorySeparatorsStartAtTheIconRowsTextColumnInBothDirections() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let renderer = ImageRenderer(content:
                SettingsControlRows(dividerLeadingInset: SettingsRowMetrics.iconTitleInset) {
                    Color.clear.frame(height: 40)
                    Color.clear.frame(height: 40)
                }
                .frame(width: 320)
                .background(Color.black)
                .environment(\.layoutDirection, direction)
                .environment(\.themePalette, .dark)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let bytes = try pixels(image)
            let lineColumns = (0..<image.width).filter { bytes[(48 * image.width + $0) * 4] > 0 }
            XCTAssertEqual(lineColumns, direction == .leftToRight ? Array(58..<320) : Array(0..<262))
        }
    }

    func testIllustratedGroupsUseSixteenPointPaddingAndGapWithoutADivider() throws {
        let renderer = ImageRenderer(content:
            SettingsControlGroup(illustrated: true) {
                Color(red: 1, green: 0, blue: 0).frame(height: 40)
                Color(red: 0, green: 1, blue: 0).frame(height: 40)
            }
            .frame(width: 320)
            .environment(\.themePalette, .dark)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bytes = try pixels(image)
        XCTAssertEqual(image.height, 128)
        let redRows = (0..<image.height).filter {
            let offset = ($0 * image.width + 160) * 4
            return bytes[offset] > 240 && bytes[offset + 1] < 10
        }
        XCTAssertEqual(redRows, Array(16..<56))
        let redColumns = (0..<image.width).filter {
            let offset = (32 * image.width + $0) * 4
            return bytes[offset] > 240 && bytes[offset + 1] < 10
        }
        XCTAssertEqual(redColumns, Array(16..<304))
        for y in 57..<72 {
            let offset = (y * image.width + 160) * 4
            let previous = ((y - 1) * image.width + 160) * 4
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(abs(Int(bytes[offset + channel]) - Int(bytes[previous + channel])), 1,
                                         "The surface gradient must not contain a separator in the 16pt gap.")
            }
        }
        let greenRows = (0..<image.height).filter {
            let offset = ($0 * image.width + 160) * 4
            return bytes[offset + 1] > 100 && bytes[offset] < 10
        }
        XCTAssertEqual(greenRows, Array(72..<112))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
