import XCTest

@MainActor
final class PlayerGestureInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--rotation-player-fixture", "--gesture-player-fixture", "--auto"]
        app.launch()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10))
        app.buttons["Open rotation player"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 25), app.debugDescription)
    }

    override func tearDown() {
        if testRun?.failureCount ?? 0 > 0 { capture("gesture-failure") }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    func testRapidTapsUseConfiguredIntervalsAndLeaveOnlyProgressVisible() {
        let forward = point(x: 0.8, y: 0.43)
        forward.doubleTap()
        for _ in 0..<3 { forward.tap() }
        let feedback = app.staticTexts["player-gesture-skip-total"]
        XCTAssertTrue(feedback.exists, app.debugDescription)
        XCTAssertEqual(feedback.label, "+20", "The configured forward interval is five seconds.")
        XCTAssertFalse(app.buttons["Pause"].exists, "The main controls must hide during skip feedback.")
        XCTAssertTrue(app.otherElements["player-gesture-progress"].exists, app.debugDescription)
        capture("forward-cumulative")
        let backward = point(x: 0.2, y: 0.43)
        backward.doubleTap()
        backward.tap()
        XCTAssertTrue(feedback.exists, app.debugDescription)
        XCTAssertTrue(feedback.label.hasPrefix("-"), app.debugDescription)
        XCTAssertFalse(app.buttons["Pause"].exists)
        capture("backward-cumulative")
    }

    func testSingleTapRevealsControlsAndNativeButtonsDoNotBecomeShortcuts() {
        point(x: 0.5, y: 0.28).tap()
        XCTAssertTrue(app.buttons["Pause"].waitForNonExistence(timeout: 3))
        point(x: 0.5, y: 0.28).tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["player-gesture-skip-total"].exists)
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
        app.buttons["Playback options"].tap()
        XCTAssertTrue(app.buttons["Playback Speed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["player-gesture-skip-total"].exists)
    }

    func testHoldAcceleratesAndReleaseRestoresRateWithoutLeavingControlsOpen() {
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 5),
                      "Verify the actual renderer is playing at 1× before holding. \(app.debugDescription)")
        XCTAssertEqual(app.staticTexts["gesture-maximum-rate"].label, "1.0")
        point(x: 0.5, y: 0.28).press(forDuration: 1.1)
        XCTAssertTrue(app.staticTexts["gesture-maximum-rate"].wait(for: \.label, toEqual: "2.0", timeout: 3),
                      app.debugDescription)
        XCTAssertTrue(app.staticTexts["gesture-rate"].wait(for: \.label, toEqual: "1.0", timeout: 3),
                      app.debugDescription)
        XCTAssertFalse(app.staticTexts["player-gesture-speed"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
        point(x: 0.5, y: 0.28).tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 3))
    }

    func testPinchFillsThenFitsSafeAreaWithoutReloadingVideo() {
        let surface = app.otherElements["gesture-pinch-area"].firstMatch
        XCTAssertTrue(app.staticTexts["gesture-video-fit"].wait(for: \.label, toEqual: "safe", timeout: 5))
        point(x: 0.5, y: 0.28).tap()
        XCTAssertTrue(app.buttons["Pause"].waitForNonExistence(timeout: 3))
        surface.pinch(withScale: 1.6, velocity: 1)
        XCTAssertTrue(app.staticTexts["gesture-video-fit"].wait(for: \.label, toEqual: "cropped", timeout: 5),
                      app.debugDescription)
        capture("edge-to-edge-fill")
        surface.pinch(withScale: 0.6, velocity: -1)
        XCTAssertTrue(app.staticTexts["gesture-video-fit"].wait(for: \.label, toEqual: "safe", timeout: 5),
                      app.debugDescription)
        XCTAssertEqual(app.staticTexts["rotation-load-count"].label, "Loads 1")
        capture("safe-area-fit")
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.staticTexts["gesture-video-fit"].wait(for: \.label, toEqual: "safe", timeout: 5))
    }

    private func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
