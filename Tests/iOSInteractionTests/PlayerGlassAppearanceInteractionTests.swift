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
                Thread.sleep(forTimeInterval: 0.7)
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
                let circleFrame = app.buttons["appearance-circle"].frame
                let circle = try pixels(screenshot.image, frame: CGRect(
                    x: circleFrame.midX - 40, y: circleFrame.midY - 40, width: 80, height: 80
                ), screen: app.frame)
                let circleReference = app.descendants(matching: .any)["appearance-reference-circle"].firstMatch
                let clear = try pixels(screenshot.image, frame: CGRect(
                    x: circleReference.frame.midX - 40, y: circleReference.frame.midY - 40, width: 80, height: 80
                ), screen: app.frame)
                XCTAssertEqual(luminance(circle), luminance(clear), accuracy: 0.03,
                               "Video controls must use untinted clear glass and white ink, including in Light mode.")
                try assertSingleGroupSurface(app, screenshot: screenshot)
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
        assertIndependentActions(app)
    }

    func testReducedEffectsGroupingInBothAppearances() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-glass-fixture"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["appearance-effects"].waitForExistence(timeout: 10))
        app.buttons["appearance-effects"].tap()
        app.buttons["appearance-video"].tap()
        for appearance in ["dark", "light"] {
            Thread.sleep(forTimeInterval: 0.7)
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Reduced effects group \(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try assertSingleGroupSurface(app, screenshot: screenshot)
            app.buttons["appearance-theme"].tap()
        }
        assertIndependentActions(app)
    }

    private func assertSingleGroupSurface(_ app: XCUIApplication, screenshot: XCUIScreenshot) throws {
        let group = app.descendants(matching: .any)["appearance-group"].firstMatch.frame
        let reference = app.descendants(matching: .any)["appearance-reference-group"].firstMatch.frame
        let actual = try groupSurface(screenshot, frame: group, screen: app.frame)
        let expected = try groupSurface(screenshot, frame: reference, screen: app.frame)
        XCTAssertEqual(actual.count, expected.count)
        let difference = zip(actual, expected).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
            / Double(max(1, actual.count)) / 255
        XCTAssertLessThan(difference, 0.04,
                          "The mixed UIKit/SwiftUI group must be one capsule, with no nested circular surfaces.")
    }

    private func assertIndependentActions(_ app: XCUIApplication) {
        app.buttons["appearance-group-left"].tap()
        app.buttons["player-playback-options"].tap()
        XCTAssertTrue(app.buttons["Fixture option"].waitForExistence(timeout: 5))
        app.buttons["Fixture option"].tap()
        XCTAssertEqual(app.buttons["appearance-group-left"].value as? String, "1")
        XCTAssertEqual(app.buttons["player-playback-options"].value as? String, "1")
    }

    private func groupSurface(_ screenshot: XCUIScreenshot, frame: CGRect, screen: CGRect) throws -> [UInt8] {
        try pixels(screenshot.image, frame: CGRect(
            x: frame.midX - 36, y: frame.midY - 22, width: 72, height: 16
        ), screen: screen)
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
            x: ((frame.minX - screen.minX) * scale).rounded(),
            y: ((frame.minY - screen.minY) * scale).rounded(),
            width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded()
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
