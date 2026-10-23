import XCTest
import UIKit

@MainActor
final class SystemDirectionalFocusTests: XCTestCase {
    func testFeaturedCardsSettleAfterHeldDirectionalNavigation() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        app.launchArguments = ["--focus-navigation-fixture", "--featured-rails"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Navigation fixture ready"].waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.down)
        let seeAll = app.buttons["See all"].firstMatch
        if seeAll.exists, seeAll.hasFocus { XCUIRemote.shared.press(.down) }
        try Self.assertFocus("Row 0 Item 0", in: app)
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: 1)
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: 1)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "featured-after-slow-navigation"
        initial.lifetime = .keepAlways
        add(initial)
        let restingGaps = try Self.featuredArtworkTopGaps(in: app)
        XCTAssertTrue(restingGaps.allSatisfy { $0 > 8 }, "The baseline must distinguish the raised first card.")
        for _ in 0..<3 {
            XCUIRemote.shared.press(.right, forDuration: 1.2)
            XCUIRemote.shared.press(.left, forDuration: 2.5)
        }
        try Self.assertFocus("Row 0 Item 0", in: app)
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "featured-after-held-directional-navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let finalGaps = try Self.featuredArtworkTopGaps(in: app)
        for (baseline, final) in zip(restingGaps, finalGaps) {
            XCTAssertEqual(final, baseline, accuracy: 1, "Previously focused cards must return to their resting painted size.")
        }
        XCUIRemote.shared.press(.right)
        try Self.assertFocus("Row 0 Item 1", in: app)
        XCTAssertTrue(app.staticTexts["Preview candidate: Row 0 Item 1"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Selected Row 0 Item 1"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Preview candidate: None"].waitForExistence(timeout: 3))
        XCUIRemote.shared.press(.down)
        let nextRow = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND hasFocus == true", "Row 1 Item "
        )).firstMatch
        XCTAssertTrue(nextRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Preview candidate: \(nextRow.label)"].waitForExistence(timeout: 3))
        #else
        throw XCTSkip("This regression uses an isolated simulator fixture.")
        #endif
    }

    private static func featuredArtworkTopGaps(in app: XCUIApplication) throws -> [CGFloat] {
        let image = app.screenshot().image
        let bitmap = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: bitmap.width * bitmap.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        let scale = CGFloat(bitmap.width) / app.frame.width
        let tops = try (0..<3).map { index -> CGFloat in
            let card = app.buttons.matching(NSPredicate(format: "label == %@", "Row 0 Item \(index)")).firstMatch
            XCTAssertTrue(card.exists)
            let x = min(bitmap.width - 1, max(0, Int(card.frame.midX * scale)))
            let y = try XCTUnwrap((0..<bitmap.height).first { y in
                let offset = (y * bitmap.width + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                return blue > 140 && blue > 2 * red && blue * 2 > green * 3
            }, "Expected the fixture's solid blue artwork for card \(index).")
            return CGFloat(y) / scale
        }
        return tops.dropFirst().map { $0 - tops[0] }
    }

    func testRemoteDirectionsDoNotRestoreThePreviousCardOrHero() throws {
        #if targetEnvironment(simulator)
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        try FocusStyleSettingsCaptureTests.withFocusStyle("Default") { _ in
            for borderless in [false, true] {
                add(try Self.exerciseDirections(in: app, borderless: borderless))
            }
        }
        #else
        throw XCTSkip("This regression uses an isolated simulator fixture.")
        #endif
    }

    static func exerciseDirections(in app: XCUIApplication, borderless: Bool) throws -> XCTAttachment {
        app.launchArguments = ["--focus-navigation-fixture"] + (borderless ? ["--borderless"] : [])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Navigation fixture ready"].waitForExistence(timeout: 15))
        let hero = app.buttons["navigation-hero"]
        XCTAssertTrue(hero.hasFocus)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 0 Item 0", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 2", in: app)
        XCUIRemote.shared.press(.left)
        try assertFocus("Row 0 Item 1", in: app)
        for index in 2...6 {
            XCUIRemote.shared.press(.right)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        for index in stride(from: 5, through: 0, by: -1) {
            XCUIRemote.shared.press(.left)
            try assertFocus("Row 0 Item \(index)", in: app)
        }
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 0 Item 1", in: app)
        XCUIRemote.shared.press(.down)
        try assertFocus("Row 1 Item 1", in: app)
        XCUIRemote.shared.press(.right)
        try assertFocus("Row 1 Item 2", in: app)
        XCUIRemote.shared.press(.up)
        try assertFocus("Row 0 Item 2", in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-directions-\(borderless ? "borderless" : "framed")"
        screenshot.lifetime = .keepAlways
        return screenshot
    }

    private static func assertFocus(_ label: String, in app: XCUIApplication) throws {
        let focused = app.buttons
            .matching(NSPredicate(format: "label == %@ AND hasFocus == true", label)).firstMatch
        XCTAssertTrue(focused.waitForExistence(timeout: 3), "Expected \(label). \(app.debugDescription)")
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertTrue(focused.exists, "Focus bounced away from \(label). \(app.debugDescription)")
    }
}
