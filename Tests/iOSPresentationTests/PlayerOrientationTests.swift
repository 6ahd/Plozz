import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class PlayerOrientationTests: XCTestCase {
    func testPreferencesAndCurrentOrientationMasksAreDifferent() {
        XCTAssertEqual(PlozziOSPlayerOrientation.mask(for: .auto), .all)
        XCTAssertEqual(PlozziOSPlayerOrientation.mask(for: PlaybackOrientation.landscape), .landscape)
        XCTAssertEqual(PlozziOSPlayerOrientation.mask(for: PlaybackOrientation.portrait), .portrait)
        for orientation in [UIInterfaceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight] {
            let mask = PlozziOSPlayerOrientation.mask(for: orientation)
            XCTAssertEqual(mask?.rawValue, 1 << orientation.rawValue)
        }
        XCTAssertNil(PlozziOSPlayerOrientation.mask(for: UIInterfaceOrientation.unknown))
    }

    func testWindowedAndOlderIPadsStayAutomatic() {
        let screen = CGSize(width: 1024, height: 1366)
        for supportsWindowLock in [false, true] {
            XCTAssertFalse(PlozziOSPlayerOrientation.supportsLock(
                idiom: .pad, supportsWindowLock: supportsWindowLock,
                windowSize: CGSize(width: 500, height: 1366), screenSize: screen
            ))
        }
        XCTAssertFalse(PlozziOSPlayerOrientation.supportsLock(
            idiom: .pad, supportsWindowLock: false, windowSize: screen, screenSize: screen
        ))
        XCTAssertTrue(PlozziOSPlayerOrientation.supportsLock(
            idiom: .pad, supportsWindowLock: true,
            windowSize: CGSize(width: 1366, height: 1024), screenSize: screen
        ))
        XCTAssertTrue(PlozziOSPlayerOrientation.supportsLock(
            idiom: .phone, supportsWindowLock: false, windowSize: screen, screenSize: screen
        ))
    }

    func testPreferenceIsSuspendedInWindowedModeAndFailureDoesNotPersist() {
        let orientation = PlozziOSPlayerOrientation(preference: .landscape)
        XCTAssertEqual(orientation.supportedMask, .all)
        orientation.updateAvailability(true)
        XCTAssertEqual(orientation.supportedMask, .landscape)
        orientation.updateAvailability(false)
        XCTAssertEqual(orientation.supportedMask, .all)
        XCTAssertEqual(orientation.preference, .landscape)
        orientation.updateAvailability(true)
        orientation.geometryRequestFailed(NSError(domain: "orientation-test", code: 1))
        XCTAssertEqual(orientation.supportedMask, .all)
        XCTAssertEqual(orientation.preference, .landscape)
        XCTAssertNotNil(orientation.status.message)
        XCTAssertNil(PlozziOSPlayerOrientation(preference: .landscape).sessionOverride)
    }

    func testHostingControllerReleasesOrientationOwnershipOnTeardown() {
        let orientation = PlozziOSPlayerOrientation(preference: .portrait)
        let host = PlozziOSOrientationHostingController(rootView: AnyView(Color.black), orientation: orientation)
        orientation.updateAvailability(true)
        XCTAssertTrue(orientation.host === host)
        XCTAssertEqual(host.supportedInterfaceOrientations, .portrait)
        host.tearDown()
        XCTAssertNil(orientation.host)
    }
}
