import XCTest

@MainActor
final class TouchFeedbackInteractionTests: XCTestCase {
    func testScrubGivesOneTickPerCommitAndPlaybackUpdatesStaySilent() throws {
        let app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        app.launchArguments = ["--touch-feedback-fixture"]
        app.launch()
        defer { app.terminate() }
        let scrubber = app.otherElements["touch-scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 1")
        XCTAssertEqual(app.staticTexts["commit-count"].label, "Commits 1")
        let previews = try XCTUnwrap(Int(app.staticTexts["preview-count"].label.split(separator: " ").last ?? ""))
        XCTAssertGreaterThan(previews, 2, "The drag must cover multiple previews, not just a tap")
        app.buttons["Playback tick"].tap()
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 1")
        end.press(forDuration: 0.1, thenDragTo: start)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")
        app.buttons["Unknown duration"].tap()
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["feedback-count"].label, "Feedback 2")
    }
}
