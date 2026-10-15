#if canImport(SwiftUI)
@testable import FeatureSettings
import XCTest

@MainActor
final class SettingsWorkspaceNavigationTests: XCTestCase {
    func testGeneralIsTheInitialSectionAndSidebarOwnsEntry() {
        let navigation = SettingsNavigationModel()
        XCTAssertEqual(navigation.section, .general)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertTrue(navigation.restoringSidebar)
        XCTAssertFalse(navigation.focusInDetail)
    }

    func testChangingSectionClearsItsChildrenButRefocusingItDoesNot() {
        let navigation = SettingsNavigationModel()
        navigation.select(.appearance)
        navigation.path = [.navigationLayout]
        navigation.select(.appearance)
        XCTAssertEqual(navigation.path, [.navigationLayout])
        navigation.select(.playback)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertEqual(navigation.section, .playback)
    }

    func testFocusReturnDoesNotChangeSectionOrNavigationPath() {
        let navigation = SettingsNavigationModel()
        navigation.select(.appearance)
        navigation.path = [.artwork]
        navigation.enterDetail()
        XCTAssertTrue(navigation.enteringDetail)
        XCTAssertFalse(navigation.focusInDetail, "A request is not native focus arrival.")
        XCTAssertFalse(navigation.restoringSidebar)
        navigation.returnToSidebar()
        XCTAssertEqual(navigation.section, .appearance)
        XCTAssertEqual(navigation.path, [.artwork])
        XCTAssertFalse(navigation.focusInDetail)
        XCTAssertTrue(navigation.restoringSidebar)
    }

    func testProfileOrAuthorizationResetDiscardsPriorDestinations() {
        let navigation = SettingsNavigationModel()
        navigation.select(.servers)
        navigation.path = [.server(key: "previous-profile-server")]
        navigation.appearanceRowID = "artwork"
        navigation.enterDetail()
        navigation.resetForProfile()
        XCTAssertEqual(navigation.section, .general)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertNil(navigation.appearanceRowID)
        XCTAssertTrue(navigation.restoringSidebar)
        XCTAssertFalse(navigation.focusInDetail)
    }

    func testHouseholdRoutesRemainUnavailableToKidsEvenAfterUnlock() {
        let routes: [SettingsRoute] = [
            .servers, .server(key: "server"), .profile, .parentalPIN,
            .metadata, .metadataDiagnostics, .seerr, .seerUserPicker(profileID: "child"),
            .syncSetup, .syncTroubleshooting, .profileSettings(profileID: "adult"),
            .profileAppearance(profileID: "adult"), .profileLockSetup(profileID: "adult")
        ]
        for route in routes {
            for sealed in [true, false] {
                XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: sealed),
                               .adultProfile, "\(route)")
            }
            XCTAssertEqual(route.access(activeProfileID: "adult", isKids: false, isParentalSealed: false),
                           .allowed, "\(route)")
        }
    }

    func testOnlySealedKidsRequirePINForTheirOwnRestrictedSettings() {
        for route: SettingsRoute in [
            .myLibraries, .plexUser(accountID: "account"), .serverUser(serverKey: "server"), .parentalPINSetup,
            .profileSettings(profileID: "child"), .profileLockSetup(profileID: "child")
        ] {
            XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: true),
                           .parentalPIN, "\(route)")
            XCTAssertEqual(route.access(activeProfileID: "child", isKids: true, isParentalSealed: false),
                           .allowed, "\(route)")
        }
        XCTAssertEqual(SettingsRoute.profileAppearance(profileID: "child")
            .access(activeProfileID: "child", isKids: true, isParentalSealed: true), .allowed)
    }
}
#endif
