import XCTest

@MainActor
final class ServerAddressNavigationInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        #if os(tvOS)
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.FocusHost")
        #else
        app = XCUIApplication(bundleIdentifier: "com.thatcube.Plozz.PresentationHost")
        #endif
    }

    override func tearDown() {
        if let testRun, testRun.failureCount > 0 {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
        app = nil
        super.tearDown()
    }

    func testSingleSignInOpensAddressEditorDirectly() {
        launch(multiple: false)
        activate(app.buttons["manageServerAddresses"])
        XCTAssertTrue(app.staticTexts["Signed in as Alice"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Original server address"].exists)
        XCTAssertTrue(app.staticTexts["https://media.example.test"].exists)
        XCTAssertFalse(app.buttons["Alice"].exists)
        capture("single-sign-in-editor")
    }

    func testMultipleSignInsAreChosenOnlyAfterTheExplicitAddressAction() {
        launch(multiple: true)
        XCTAssertFalse(app.buttons["Alice"].exists)
        XCTAssertFalse(app.buttons["Bob"].exists)
        capture("address-management-entry")
        activate(app.buttons["manageServerAddresses"])
        let bob = app.buttons["Bob"].firstMatch
        XCTAssertTrue(bob.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(
            app.sheets["Choose a sign-in"].exists || app.staticTexts["Choose a sign-in"].exists,
            app.debugDescription
        )
        capture("sign-in-chooser")
        activate(bob)
        XCTAssertTrue(app.staticTexts["Signed in as Bob"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Signed in as Alice"].exists)
        capture("selected-sign-in-editor")
    }

    private func launch(multiple: Bool) {
        app.launchArguments = ["--server-address-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if multiple { app.launchArguments.append("--multiple-address-signins") }
        app.launch()
        XCTAssertTrue(app.buttons["manageServerAddresses"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func activate(_ target: XCUIElement) {
        #if os(tvOS)
        for _ in 0..<8 {
            if target.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(target.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        #else
        target.tap()
        #endif
    }

    private func capture(_ name: String) {
        // Let native sheet and focus animations finish before retaining visual evidence.
        Thread.sleep(forTimeInterval: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "server-addresses-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
