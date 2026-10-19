import UIKit
import XCTest

@MainActor
final class PlayerLayoutInteractionTests: XCTestCase {
    func testNativePlayerGeometryMatchesReferenceAndSurvivesRotation() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-layout-fixture"]
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 10))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
                && app.buttons["Close player"].frame.minY < 40
        }, object: nil)], timeout: 10)
        capture(app, name: "Native player landscape")
        var measurements: [String] = []
        for name in ["Close player", "Skip backward", "Play", "Skip forward", "Info", "Cast", "Episodes", "Playlist", "Subtitles"] {
            let button = app.buttons[name]
            XCTAssertTrue(button.exists, name)
            measurements.append("\(name): \(button.frame)")
        }
        let timeline = app.descendants(matching: .any)["player-timeline"].firstMatch.frame
        measurements.append("timeline: \(timeline)")
        let play = app.buttons["Play"].frame
        let compact = app.frame.height < 400
        XCTAssertEqual(play.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(play.midY, app.frame.midY, accuracy: 1)
        XCTAssertEqual(play.width, compact ? 44 : 92, accuracy: 1)
        XCTAssertEqual(app.buttons["Skip backward"].frame.midX, play.midX - (compact ? 64 : 146), accuracy: 1)
        XCTAssertEqual(app.buttons["Skip forward"].frame.midX, play.midX + (compact ? 64 : 146), accuracy: 1)
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any)["player-timeline-scrubber"].firstMatch.frame.height, 44
        )
        if app.frame.size == CGSize(width: 956, height: 440) {
            let close = app.buttons["Close player"].frame
            XCTAssertEqual(close.minX, 62, accuracy: 1)
            XCTAssertEqual(close.minY, 24, accuracy: 1)
            XCTAssertEqual(close.width, 44, accuracy: 1)
            let info = app.buttons["Info"].frame
            XCTAssertEqual(info.minX, 62, accuracy: 1)
            XCTAssertEqual(info.minY, 372, accuracy: 1)
            XCTAssertEqual(info.height, 44, accuracy: 1)
            XCTAssertEqual(info.width, 56, accuracy: 1)
            XCTAssertEqual(timeline.midY, 353, accuracy: 1)
        }
        attachMeasurements(measurements)
        XCUIDevice.shared.orientation = .portrait
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width < app.frame.height
                && app.buttons["Close player"].frame.minX < 40
        }, object: nil)], timeout: 10)
        capture(app, name: "Native player portrait")
        XCTAssertEqual(app.buttons["Play"].frame.midY, app.frame.midY, accuracy: 1)
        XCTAssertTrue(app.buttons["Skip backward"].isHittable)
        XCTAssertTrue(app.buttons["Skip forward"].isHittable)
        XCTAssertTrue(app.buttons["Subtitles"].isHittable)
        XCTAssertTrue(app.buttons["player-playback-options"].isHittable)
        if app.frame.size == CGSize(width: 440, height: 956) {
            XCTAssertEqual(app.buttons["Close player"].frame.minX, 21, accuracy: 1)
            XCTAssertEqual(app.buttons["Close player"].frame.minY, 62, accuracy: 1)
            XCTAssertEqual(app.buttons["Skip backward"].frame.midX, 103, accuracy: 1)
            XCTAssertEqual(app.buttons["Skip forward"].frame.midX, 337, accuracy: 1)
            XCTAssertEqual(app.buttons["Info"].frame.minX, 21, accuracy: 1)
            XCTAssertEqual(app.buttons["Info"].frame.minY, 878, accuracy: 1)
            XCTAssertEqual(app.descendants(matching: .any)["player-timeline"].firstMatch.frame.midY, 859, accuracy: 1)
            let info = app.buttons["Info"].frame
            let image = XCUIScreen.main.screenshot().image
            let glass = try visibleBounds(image, in: info, screen: app.frame, threshold: 20)
            XCTAssertEqual(glass.width, 56, accuracy: 1)
            XCTAssertEqual(glass.height, 42, accuracy: 1,
                           "Compare the visible glass, not the outer touch target.")
            let ink = try visibleBounds(image, in: info, screen: app.frame, threshold: 180)
            XCTAssertEqual(ink.width, 25.3, accuracy: 1)
            XCTAssertEqual(ink.height, 11, accuracy: 1)
            let current = app.buttons["player-timeline-current-time"].frame
            let end = app.buttons["player-timeline-end-time"].frame
            let scrubber = app.descendants(matching: .any)["player-timeline-scrubber"].firstMatch.frame
            XCTAssertEqual(current.width, 44, accuracy: 1)
            XCTAssertEqual(end.width, 44, accuracy: 1)
            XCTAssertEqual(scrubber.width, 302, accuracy: 1,
                           "Unused long-duration time columns must not squeeze the portrait track.")
            XCTAssertEqual(scrubber.minX - current.maxX, 4, accuracy: 1)
            XCTAssertEqual(end.minX - scrubber.maxX, 4, accuracy: 1)
            let currentInk = try visibleBounds(image, in: current, screen: app.frame, threshold: 130)
            let endInk = try visibleBounds(image, in: end, screen: app.frame, threshold: 130)
            XCTAssertEqual(current.minX + currentInk.minX, info.minX, accuracy: 2)
            XCTAssertEqual(end.minX + endInk.maxX, 419, accuracy: 2)
        }
        let tabs = ["Info", "Cast", "Episodes", "Playlist"].map { app.buttons[$0] }
        for tab in tabs {
            XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        }
        for (left, right) in zip(tabs, tabs.dropFirst()) {
            XCTAssertEqual(right.frame.minX - left.frame.maxX, 8, accuracy: 1)
        }
        attachMeasurements(["Portrait"] + ["Close player", "Skip backward", "Play", "Skip forward", "Info", "Cast", "Episodes", "Playlist", "Subtitles"]
            .map { "\($0): \(app.buttons[$0].frame)" })
    }

    private func visibleBounds(_ image: UIImage, in frame: CGRect, screen: CGRect, threshold: UInt8) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(cgImage.width) / screen.width
        let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(
            x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale
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
        var minX = crop.width, minY = crop.height, maxX = -1, maxY = -1
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                let offset = (y * crop.width + x) * 4
                if min(bytes[offset], bytes[offset + 1], bytes[offset + 2]) > threshold {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX)
        return CGRect(
            x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale
        )
    }

    private func attachMeasurements(_ lines: [String]) {
        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "Control frames in points"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
