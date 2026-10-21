import UIKit
import XCTest

@MainActor
final class ProfilePickerInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
    }

    override func tearDown() async throws {
        if app.state == .runningForeground {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.lifetime = .keepAlways
            add(image)
        }
        app.terminate()
        app = nil
        try await super.tearDown()
    }

    func testSelectionCancelAndFreshPresentation() {
        launch()
        XCTAssertFalse(app.staticTexts["Choose a profile to continue."].exists)
        app.buttons["Alex"].tap()
        XCTAssertTrue(app.staticTexts["fixture-profile-result"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["fixture-profile-result"].label, "Alex")
        app.buttons["Open picker"].tap()
        XCTAssertTrue(app.buttons["Sam"].waitForExistence(timeout: 3))
        app.buttons["profile-picker-close"].tap()
        XCTAssertEqual(app.staticTexts["fixture-profile-result"].label, "Cancelled")
    }

    func testEditModeAndLongPressPushOneProfilePage() {
        launch()
        app.buttons["profile-picker-edit"].tap()
        XCTAssertFalse(app.buttons["Add Profile"].exists)
        XCTAssertFalse(app.buttons["profile-picker-close"].exists)
        app.buttons["Alex"].tap()
        XCTAssertTrue(app.navigationBars["Alex"].waitForExistence(timeout: 3), app.debugDescription)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["profile-picker-edit"].waitForExistence(timeout: 3))
        app.buttons["profile-picker-edit"].tap()
        XCTAssertTrue(app.buttons["Add Profile"].waitForExistence(timeout: 3))
        app.buttons["Sam"].press(forDuration: 1)
        app.buttons["Edit Profile"].tap()
        XCTAssertTrue(app.navigationBars["Sam"].waitForExistence(timeout: 3))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["Alex"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists)
    }

    func testAdultAndKidsCreationRemainSeparateEntryPoints() {
        for title in ["Add Profile", "Add Kids Profile"] {
            launch()
            app.buttons[title].tap()
            XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertTrue(app.textFields.firstMatch.exists, app.debugDescription)
            app.buttons["Cancel"].tap()
            if app.alerts["Discard changes?"].waitForExistence(timeout: 1) {
                app.alerts.buttons["Discard"].tap()
            }
            XCTAssertTrue(app.staticTexts["fixture-profile-result"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["fixture-profile-result"].label, "Cancelled")
        }
    }

    func testRestrictedLaunchPickerExposesNoManagementOrDismissal() {
        launch(["--restricted-picker", "--launch-picker"])
        XCTAssertFalse(app.buttons["profile-picker-edit"].exists)
        XCTAssertFalse(app.buttons["profile-picker-close"].exists)
        XCTAssertFalse(app.buttons["Add Profile"].exists)
        XCTAssertFalse(app.buttons["Add Kids Profile"].exists)
        app.buttons["Jamie"].tap()
        XCTAssertTrue(app.staticTexts["fixture-profile-result"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["fixture-profile-result"].label, "Jamie")
    }

    func testPlexPINStaysInsidePickerAndCancelReturnsToProfiles() throws {
        app.launchArguments = ["--profile-selection-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10))
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5))
        for digit in ["2", "4", "6", "8"] { app.buttons[digit].tap() }
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
    }

    func testProfilePINFlowsDirectlyIntoPlexPINBeforeCompletion() throws {
        app.launchArguments = ["--profile-selection-fixture", "--two-pins"]
        app.launch()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10))
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 5))
        try assertHomeIsCovered()
        for digit in ["1", "2", "3", "4"] { app.buttons[digit].tap() }
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        for digit in ["2", "4", "6", "8"] { app.buttons[digit].tap() }
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
    }

    func testLaunchPickerCancellationStaysInsideSelectionUntilAnotherProfileIsChosen() throws {
        app.launchArguments = ["--profile-selection-fixture", "--launch-selection"]
        app.launch()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10))
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Alex"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["profile-picker-close"].exists)
        try assertHomeIsCovered()
        app.buttons["Alex"].tap()
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
    }

    func testInitialProfileLockWaitsForTapThenContinuesToPlex() throws {
        app.launchArguments = [
            "--profile-selection-fixture", "--launch-selection", "--two-pins",
            "--initial-profile-lock"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["1"].exists, "An existing lock must wait for an explicit profile tap.")
        XCTAssertFalse(app.buttons["profile-picker-close"].exists)
        try assertHomeIsCovered()
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.buttons["1"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        for digit in ["1", "2", "3", "4"] { app.buttons[digit].tap() }
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        for digit in ["2", "4", "6", "8"] { app.buttons[digit].tap() }
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
    }

    func testPendingPlexRequestWaitsForAnExplicitProfileTap() throws {
        for launchArguments in [[], ["--launch-selection"]] {
            if app.state != .notRunning { app.terminate() }
            app.launchArguments = ["--profile-selection-fixture", "--initial-plex-pin"] + launchArguments
            app.launch()
            XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.staticTexts["Enter your Plex PIN"].exists)
            XCTAssertFalse(app.buttons["1"].exists)
            try assertHomeIsCovered()
            app.buttons["Protected"].tap()
            XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5))
            try assertHomeIsCovered()
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Alex"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["1"].exists)
            app.buttons["Alex"].tap()
            let result = app.staticTexts["fixture-selection-result"]
            XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
            XCTAssertEqual(result.label, "Selected")
        }
    }

    func testPendingProfileLockDoesNotPreventChoosingADifferentProfile() throws {
        app.launchArguments = [
            "--profile-selection-fixture", "--launch-selection", "--two-pins",
            "--initial-profile-lock"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Alex"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["1"].exists)
        try assertHomeIsCovered()
        app.buttons["Alex"].tap()
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
        XCTAssertFalse(app.buttons["1"].exists)
    }

    func testCancellingPlexWithLockedFallbackAllowsANewSelection() throws {
        app.launchArguments = ["--profile-selection-fixture", "--locked-fallback"]
        app.launch()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 10))
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Protected"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        app.buttons["Protected"].tap()
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].waitForExistence(timeout: 5), app.debugDescription)
        try assertHomeIsCovered()
        for digit in ["2", "4", "6", "8"] { app.buttons[digit].tap() }
        let result = app.staticTexts["fixture-selection-result"]
        XCTAssertTrue(result.wait(for: \.isHittable, toEqual: true, timeout: 8), app.debugDescription)
        XCTAssertEqual(result.label, "Selected")
    }

    private func assertHomeIsCovered(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(app.staticTexts["fixture-selection-result"].isHittable, file: file, line: line)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "picker-or-pin-covered"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage)
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &rgba, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let exposedHome = stride(from: 0, to: rgba.count, by: 4).filter {
            rgba[$0] > 180 && rgba[$0 + 1] < 80 && rgba[$0 + 2] > 180
        }.count
        XCTAssertLessThan(exposedHome, 10, "The magenta Home backdrop must remain covered.", file: file, line: line)
    }

    private func launch(_ arguments: [String] = []) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["--profile-picker-fixture"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Alex"].waitForExistence(timeout: 10), app.debugDescription)
    }
}
