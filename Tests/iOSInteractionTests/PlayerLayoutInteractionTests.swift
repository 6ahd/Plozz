import UIKit
import XCTest

@MainActor
final class PlayerLayoutInteractionTests: XCTestCase {
    func testInfoAndCastDoNotAddALightBackingOverDarkVideo() throws {
        try assertInfoAndCastAppearance(whiteVideo: false)
    }

    func testInfoAndCastRemainReadableOverBrightVideo() throws {
        try assertInfoAndCastAppearance(whiteVideo: true)
    }

    private func assertInfoAndCastAppearance(whiteVideo: Bool) throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        let backdrop = whiteVideo ? "white" : "black"
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for appearance in ["light", "dark"] {
                app.launchArguments = ["--player-layout-fixture", "--\(appearance)"]
                if whiteVideo { app.launchArguments.append("--white-video") }
                app.launch()
                XCTAssertTrue(app.buttons["Info"].waitForExistence(timeout: 10))
                app.buttons["Info"].tap()
                let title = app.staticTexts["Now Playing"]
                XCTAssertTrue(title.waitForExistence(timeout: 5))
                capture(app, name: "Info \(appearance) \(orientation.rawValue) over \(backdrop) video")
                let titleFrame = title.frame
                let infoImage = uprightImage(XCUIScreen.main.screenshot().image, screen: app.frame)
                let infoBackground = try brightness(infoImage, in: CGRect(
                    x: titleFrame.minX - 8, y: titleFrame.midY - 2, width: 4, height: 4
                ), screen: app.frame)
                XCTAssertLessThan(infoBackground, whiteVideo ? 0.8 : 0.45,
                                  "Info must retain separation between the dimmed video and light text.")
                let infoInk = try visibleBounds(infoImage, in: titleFrame,
                                                screen: app.frame, threshold: 230)
                XCTAssertGreaterThan(infoInk.width, 20, "Info must retain legible video-overlay text.")
                app.buttons["Cast"].tap()
                let face = app.buttons["player-cast-face-actor"]
                XCTAssertTrue(face.waitForExistence(timeout: 5))
                capture(app, name: "Cast \(appearance) \(orientation.rawValue) over \(backdrop) video")
                let faceFrame = face.frame
                let castImage = uprightImage(XCUIScreen.main.screenshot().image, screen: app.frame)
                let castBackground = try brightness(castImage, in: CGRect(
                    x: faceFrame.minX + 8, y: faceFrame.midY - 2, width: 4, height: 4
                ), screen: app.frame)
                XCTAssertLessThan(castBackground, whiteVideo ? 0.8 : 0.45,
                                  "Cast must use the same unpainted video surface as Info.")
                let castInk = try visibleBounds(castImage, in: app.staticTexts["Actor"].firstMatch.frame,
                                                screen: app.frame, threshold: 230)
                XCTAssertGreaterThan(castInk.width, 20, "Cast names must remain readable in Light mode.")
                face.tap()
                XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
                capture(app, name: "Cast detail \(appearance) \(orientation.rawValue) over \(backdrop) video")
                app.buttons["Back"].tap()
                XCTAssertTrue(face.waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }

    func testPlaybackRolloversDoNotMoveTheScrubber() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        defer { app.terminate() }
        for longVideo in [false, true] {
            app.launchArguments = ["--player-layout-fixture", "--timeline-rollovers"]
            if longVideo { app.launchArguments.append("--long-video") }
            app.launch()
            let current = app.buttons["player-timeline-current-time"]
            let remaining = app.buttons["player-timeline-end-time"]
            let advance = app.buttons["fixture-next-time"]
            XCTAssertTrue(current.waitForExistence(timeout: 10))
            let scrubber = app.descendants(matching: .any)["player-timeline-scrubber"].firstMatch
            let currentFrame = current.frame
            let remainingFrame = remaining.frame
            let scrubberFrame = scrubber.frame
            for step in 1...(longVideo ? 10 : 6) {
                advance.tap()
                wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    advance.value as? String == "\(step)"
                }, object: nil)], timeout: 5)
                XCTAssertEqual(current.frame, currentFrame)
                XCTAssertEqual(remaining.frame, remainingFrame)
                XCTAssertEqual(scrubber.frame, scrubberFrame,
                               "Playback ticks must not move or resize the actual scrubber hit target.")
            }
            XCTAssertEqual(current.value as? String, longVideo ? "1:30:00" : "20:00")
            XCTAssertEqual(remaining.value as? String, longVideo ? "-0:00:00" : "-00:00")
            app.terminate()
        }
    }

    func testTimeLabelsUseTheVideoDurationFromTheStart() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        defer { app.terminate() }
        for longVideo in [false, true] {
            app.launchArguments = ["--player-layout-fixture"]
            if longVideo { app.launchArguments.append("--long-video") }
            app.launch()
            let current = app.buttons["player-timeline-current-time"]
            let remaining = app.buttons["player-timeline-end-time"]
            XCTAssertTrue(current.waitForExistence(timeout: 10))
            XCTAssertEqual(current.value as? String, longVideo ? "0:10:00" : "10:00")
            XCTAssertEqual(remaining.value as? String, longVideo ? "-1:20:00" : "-10:00")
            capture(app, name: longVideo ? "Hour-plus timeline" : "Short episode timeline")
            app.terminate()
        }
    }

    func testNativeAVKitPlayerAppearanceInLightAndDark() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        defer { app.terminate() }
        for appearance in ["light", "dark"] {
            app.launchArguments = ["--player-layout-fixture", "--native-avkit", "--\(appearance)"]
            app.launch()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
            capture(app, name: "AVKit native \(appearance)")
            attachMeasurements([app.debugDescription])
            app.terminate()
        }
    }

    func testPlayerLayoutAppearanceOverVideo() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        for appearance in ["light", "dark"] {
            app.launchArguments = ["--player-layout-fixture", "--video", "--\(appearance)"]
            app.launch()
            XCTAssertTrue(app.buttons["Info"].waitForExistence(timeout: 10))
            capture(app, name: "Plozz \(appearance) controls over video portrait")
            XCUIDevice.shared.orientation = .landscapeLeft
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.frame.width > app.frame.height
            }, object: nil)], timeout: 10)
            capture(app, name: "Plozz \(appearance) controls over video landscape")
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testLightControlsRemainLegibleOverWhiteVideo() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--player-layout-fixture", "--white-video", "--light"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        capture(app, name: "Plozz light controls over white video")
        let image = XCUIScreen.main.screenshot().image
        for name in ["Play", "Skip backward", "Skip forward"] {
            let ink = try visibleBounds(image, in: app.buttons[name].frame.insetBy(dx: 12, dy: 12),
                                        screen: app.frame, threshold: 230)
            XCTAssertGreaterThan(ink.width, 20, "\(name) must retain visible white ink over bright video.")
            XCTAssertGreaterThan(ink.height, 20)
        }
    }

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

    private func uprightImage(_ image: UIImage, screen: CGRect) -> UIImage {
        UIGraphicsImageRenderer(size: screen.size).image { context in
            if screen.width > screen.height, let source = image.cgImage,
               source.width < source.height {
                // Screen captures retain portrait pixels in landscapeLeft.
                context.cgContext.translateBy(x: 0, y: screen.height)
                context.cgContext.rotate(by: -.pi / 2)
                UIImage(cgImage: source).draw(in: CGRect(
                    x: 0, y: 0, width: screen.height, height: screen.width
                ))
            } else {
                image.draw(in: CGRect(origin: .zero, size: screen.size))
            }
        }
    }

    private func brightness(_ image: UIImage, in frame: CGRect, screen: CGRect) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(source.width) / screen.width
        let crop = try XCTUnwrap(source.cropping(to: CGRect(
            x: (frame.minX - screen.minX) * scale, y: (frame.minY - screen.minY) * scale,
            width: frame.width * scale, height: frame.height * scale
        ).integral))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) {
            $0 + Double(bytes[$1]) * 0.2126 + Double(bytes[$1 + 1]) * 0.7152 + Double(bytes[$1 + 2]) * 0.0722
        } / Double(crop.width * crop.height) / 255
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
        Thread.sleep(forTimeInterval: 0.7)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
