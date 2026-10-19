import UIKit
import XCTest

@MainActor
final class PlayerGlassAppearanceInteractionTests: XCTestCase {
    func testPlayerGlassMatchesNativeCompositorAcrossThemesAndVideo() throws {
        XCUIDevice.shared.orientation = .portrait
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
                    sample[name] = bytes
                }
                let reference = app.descendants(matching: .any)["appearance-reference"].firstMatch
                XCTAssertTrue(reference.exists)
                let native = try pixels(screenshot.image, frame: reference.frame, screen: app.frame)
                let panel = try XCTUnwrap(sample["panel"])
                XCTAssertEqual(luminance(panel), luminance(native), accuracy: 0.05,
                               "Player glass must match stock regular glass, not a forced dark material.")
                if backdrop == "black" {
                    let group = app.descendants(matching: .any)["appearance-group"].firstMatch.frame
                    let bridge = try pixels(screenshot.image, frame: CGRect(
                        x: group.midX - 8, y: group.midY - 8, width: 16, height: 16
                    ), screen: app.frame)
                    XCTAssertGreaterThan(luminance(bridge), 0.03,
                                         "Adjacent controls must share glass across the gap, not isolated circles.")
                }
                samples.append(sample)
                app.buttons["appearance-theme"].tap()
            }
            for name in samples[0].keys {
                let first = try XCTUnwrap(samples[0][name])
                let second = try XCTUnwrap(samples[1][name])
                XCTAssertEqual(first.count, second.count)
            }
            if backdrop == "white" { app.buttons["appearance-video"].tap() }
        }
        app.buttons["appearance-group-left"].tap()
        app.buttons["appearance-group-right"].tap()
        XCTAssertEqual(app.buttons["appearance-group-left"].value as? String, "1")
        XCTAssertEqual(app.buttons["appearance-group-right"].value as? String, "1")
    }

    private func luminance(_ bytes: [UInt8]) -> Double {
        stride(from: 0, to: bytes.count, by: 4).reduce(0.0) {
            $0 + Double(bytes[$1]) * 0.2126 + Double(bytes[$1 + 1]) * 0.7152 + Double(bytes[$1 + 2]) * 0.0722
        } / Double(max(1, bytes.count / 4)) / 255
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
