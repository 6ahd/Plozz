import CoreUI
import SwiftUI
import UIKit
import XCTest

@MainActor
final class SettingsControlRowsHostedTests: XCTestCase {
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
            let expected = count < 2 ? [] : Array([83, 130].prefix(count - 1))
            XCTAssertEqual(lineRows, expected,
                           "\(count) rows: separate only adjacent controls, after the first row's helper.")
        }
    }

    func testFocusFillLeavesThreePointsOnEitherSideOfTheDivider() throws {
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
            let top = focused * 47
            XCTAssertEqual(whiteRows, Array(top..<(top + 40)),
                           "The focus fill must not bleed into the shared 3pt divider clearance.")
            for dividerY in [43, 90] {
                XCTAssertGreaterThan(bytes[(dividerY * image.width + 160) * 4], 0)
                for y in [dividerY - 3, dividerY - 2, dividerY - 1, dividerY + 1, dividerY + 2, dividerY + 3] {
                    XCTAssertEqual(bytes[(y * image.width + 160) * 4], 0)
                }
            }
        }
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
