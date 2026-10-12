import XCTest

@MainActor
final class PlayerRotationInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
    }

    override func tearDown() {
        if let testRun, testRun.failureCount > 0 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    func testAutoRotatesExistingPlayerAndSessionLockResetsOnReopen() {
        launch()
        openPlayer()
        rotate(.landscapeLeft)
        chooseRotationAction("Lock rotation")
        assertLockState("locked")
        XCUIDevice.shared.orientation = .portrait
        assertStaysLandscape(true)
        chooseRotationAction("Unlock rotation")
        rotate(.landscapeRight)
        rotate(.portrait)
        XCTAssertEqual(app.staticTexts["rotation-load-count"].label, "Loads 1")
        chooseRotationAction("Lock rotation")
        closePlayer()
        XCTAssertEqual(app.staticTexts["saved-orientation"].label, "auto")
        openPlayer()
        assertLockState("auto")
        rotate(.landscapeLeft)
        XCTAssertEqual(app.staticTexts["rotation-load-count"].label, "Loads 2")
    }

    func testLandscapePreferenceAllowsBothSidesAndUnlockDoesNotPersist() {
        launch("--landscape")
        openPlayer()
        if UIDevice.current.userInterfaceIdiom == .pad {
            assertOrientation(landscape: false)
            rotate(.landscapeLeft)
            rotate(.landscapeRight)
            rotate(.portrait)
            assertLockState("auto")
            closePlayer()
            XCTAssertEqual(app.staticTexts["saved-orientation"].label, "landscape")
            return
        }
        assertOrientation(landscape: true)
        rotate(.landscapeLeft)
        rotate(.landscapeRight)
        XCUIDevice.shared.orientation = .portrait
        assertStaysLandscape(true)
        chooseRotationAction("Unlock rotation")
        rotate(.landscapeLeft)
        rotate(.portrait)
        XCTAssertEqual(app.staticTexts["rotation-load-count"].label, "Loads 1")
        closePlayer()
        XCTAssertEqual(app.staticTexts["saved-orientation"].label, "landscape")
        assertOrientation(landscape: false, player: false)
        openPlayer()
        assertOrientation(landscape: true)
        assertLockState("locked")
    }

    func testPortraitPreferenceDoesNotLockBrowsingAfterDismissal() {
        launch("--portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertOrientation(landscape: true, player: false)
        openPlayer()
        if UIDevice.current.userInterfaceIdiom == .pad {
            assertOrientation(landscape: true)
            rotate(.portrait)
            rotate(.landscapeRight)
            assertLockState("auto")
            closePlayer()
            XCTAssertEqual(app.staticTexts["saved-orientation"].label, "portrait")
            return
        }
        assertOrientation(landscape: false)
        XCUIDevice.shared.orientation = .landscapeRight
        assertStaysLandscape(false)
        closePlayer()
        XCUIDevice.shared.orientation = .portrait
        rotate(.landscapeLeft, player: false)
        XCTAssertEqual(app.staticTexts["saved-orientation"].label, "portrait")
    }

    private func launch(_ preference: String? = nil) {
        app.launchArguments = ["--rotation-player-fixture"] + (preference.map { [$0] } ?? [])
        app.launch()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10))
    }

    private func openPlayer() {
        app.buttons["Open rotation player"].tap()
        XCTAssertTrue(app.otherElements["rotation-video-surface"].firstMatch.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 25), app.debugDescription)
    }

    private func revealControls() {
        if !app.buttons["Playback options"].isHittable {
            app.otherElements["rotation-video-surface"].firstMatch.tap()
        }
    }

    private func chooseRotationAction(_ title: String) {
        revealControls()
        app.buttons["Playback options"].tap()
        let action = app.buttons[title]
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        action.tap()
    }

    private func closePlayer() {
        revealControls()
        app.buttons["Close player"].tap()
        XCTAssertTrue(app.buttons["Open rotation player"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func rotate(_ orientation: UIDeviceOrientation, player: Bool = true) {
        XCUIDevice.shared.orientation = orientation
        assertOrientation(landscape: orientation.isLandscape, player: player)
        if player {
            let expected: String
            switch orientation {
            case .landscapeLeft: expected = String(UIInterfaceOrientation.landscapeRight.rawValue)
            case .landscapeRight: expected = String(UIInterfaceOrientation.landscapeLeft.rawValue)
            default: expected = String(UIInterfaceOrientation.portrait.rawValue)
            }
            XCTAssertTrue(app.staticTexts["rotation-interface-orientation"].wait(
                for: \.label, toEqual: expected, timeout: 10
            ))
        }
    }

    private func assertLockState(_ value: String) {
        XCTAssertTrue(app.staticTexts["rotation-lock-state"].wait(for: \.label, toEqual: value, timeout: 5))
    }

    private func assertOrientation(landscape: Bool, player: Bool = true) {
        let predicate = NSPredicate { [self] _, _ in
            MainActor.assumeIsolated {
                let window = app.windows.firstMatch.frame
                guard (window.width > window.height) == landscape else { return false }
                guard player else { return true }
                let surface = app.otherElements["rotation-video-surface"].firstMatch.frame
                return (surface.width > surface.height) == landscape
                    && surface.width > window.width * 0.85 && surface.height > window.height * 0.85
            }
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10),
            .completed, app.debugDescription
        )
    }

    private func assertStaysLandscape(_ landscape: Bool) {
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            MainActor.assumeIsolated {
                let frame = app.windows.firstMatch.frame
                return (frame.width > frame.height) != landscape
            }
        }, object: nil)
        rotated.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 2), .completed)
    }
}
