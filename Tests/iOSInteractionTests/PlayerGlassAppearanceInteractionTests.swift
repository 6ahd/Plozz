import UIKit
import XCTest

@MainActor
final class PlayerGlassAppearanceInteractionTests: XCTestCase {
    func testNativeGlassKeepsDarkCompositorOutputAcrossThemes() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-glass-fixture"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["appearance-theme"].waitForExistence(timeout: 10))
        for backdrop in ["white", "black"] {
            var samples: [[String: [UInt8]]] = []
            for scheme in ["dark", "light"] {
                let screenshot = app.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "Native player \(scheme) over \(backdrop)"
                attachment.lifetime = .keepAlways
                add(attachment)
                var sample: [String: [UInt8]] = [:]
                for name in ["circle", "tab", "native-button", "track", "panel"] {
                    let element = app.descendants(matching: .any)["appearance-\(name)"].firstMatch
                    XCTAssertTrue(element.exists, name)
                    let bytes = try pixels(screenshot.image, frame: element.frame, screen: app.frame)
                    let level = stride(from: 0, to: bytes.count, by: 4).reduce(0.0) {
                        $0 + Double(bytes[$1]) / 255
                    } / Double(bytes.count / 4)
                    XCTAssertLessThan(level, 0.65, "\(name) must stay dark over \(backdrop) in \(scheme).")
                    sample[name] = bytes
                }
                let prominent = app.buttons["appearance-prominent"]
                let prominentPixels = try pixels(screenshot.image, frame: CGRect(
                    x: prominent.frame.midX - 8, y: prominent.frame.midY - 8, width: 16, height: 16
                ), screen: app.frame)
                let ink = stride(from: 0, to: prominentPixels.count, by: 4).reduce(0.0) {
                    $0 + Double(prominentPixels[$1]) / 255
                } / Double(prominentPixels.count / 4)
                XCTAssertLessThan(ink, 0.3, "The prominent control needs dark ink, not a white icon on white glass.")
                samples.append(sample)
                app.buttons["appearance-theme"].tap()
            }
            for name in samples[0].keys {
                let first = try XCTUnwrap(samples[0][name])
                let second = try XCTUnwrap(samples[1][name])
                XCTAssertEqual(first.count, second.count)
                let difference = zip(first, second).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
                    / Double(first.count) / 255
                XCTAssertLessThan(difference, 0.025, name)
            }
            if backdrop == "white" { app.buttons["appearance-video"].tap() }
        }
    }

    private func pixels(_ image: UIImage, frame: CGRect, screen: CGRect) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(image.width) / screen.width
        let frame = frame.insetBy(dx: 5, dy: 5)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: (frame.minX - screen.minX) * scale, y: (frame.minY - screen.minY) * scale,
            width: frame.width * scale, height: frame.height * scale
        )))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return bytes
    }
}
