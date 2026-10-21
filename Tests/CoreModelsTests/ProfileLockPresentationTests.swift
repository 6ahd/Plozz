import XCTest
@testable import CoreModels

final class ProfileLockPresentationTests: XCTestCase {
    func testLocalPlexCombinedAndUnprotectedLockHints() {
        var profile = Profile(name: "Viewer")
        XCTAssertFalse(profile.showsPINLock)
        profile.lock = ProfileLock.make(pin: "1234", iterations: 1)
        XCTAssertTrue(profile.showsPINLock)
        profile = profile.settingHomeUserBinding(
            .init(homeUserID: "viewer", name: "Viewer", requiresPIN: true), forPlexAccount: "plex"
        )
        XCTAssertTrue(profile.showsPINLock)
        profile.lock = nil
        XCTAssertFalse(profile.isLocked, "The presentation hint must not create a separate Plozz PIN gate.")
        XCTAssertTrue(profile.showsPINLock)
        profile = profile.settingHomeUserBinding(
            .init(homeUserID: "viewer", name: "Viewer", requiresPIN: false), forPlexAccount: "plex"
        )
        XCTAssertFalse(profile.showsPINLock)
    }

    func testLegacyBindingsRemainSupportedAndAuthoritativeBindingsWin() {
        var profile = Profile(
            name: "Viewer", plexHomeUserID: "viewer", plexHomeUserAccountID: "plex",
            plexHomeUserRequiresPIN: true
        )
        XCTAssertTrue(profile.showsPINLock)
        profile.plexHomeUserBindings = [
            "plex": .init(homeUserID: "viewer", name: "Viewer", requiresPIN: false)
        ]
        XCTAssertFalse(profile.showsPINLock, "The authoritative binding overrides stale legacy protection.")
    }
}
