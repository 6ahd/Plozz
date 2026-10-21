#if os(iOS)
import CoreModels
import FeatureAuth
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class ProfileSelectionPerformanceTests: XCTestCase {
    func testPerformanceProfileSelection() async throws {
        try PerformanceProbe.requireEnabled()
        let suite = "ProfileSelectionPerformance.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProfileStore(defaults: defaults)
        let profiles = ProfilesModel(store: store)
        let accounts = AccountStore(secureStore: InMemorySecureStore())
        try accounts.add(Account(
            id: "profile-performance-plex",
            server: MediaServer(
                id: "fixture", name: "Fixture",
                baseURL: URL(string: "https://plex.example")!, provider: .plex
            ), userID: "owner", userName: "Owner", deviceID: "fixture"
        ), token: "FIXTURE-OWNER")
        let binding = PlexHomeUserBinding(
            homeUserID: "protected", name: "Protected", requiresPIN: true, pinRequirementVerified: true
        )
        let targets = (0..<16).map { index in
            var profile = profiles.add(name: "Viewer \(index)", avatarSymbol: "person.fill", colorIndex: index % 5)
            profile = profile.settingHomeUserBinding(binding, forPlexAccount: "profile-performance-plex")
            profiles.update(profile)
            profiles.setActiveAccountIDs(["profile-performance-plex"], for: profile.id)
            return profile.id
        }
        let app = PlozziOSAppModel(accountStore: accounts, profileStore: store)
        app.plexHomeUsers.plexHomeUsersFetch = { _, _ in
            try await Task.sleep(for: .milliseconds(5))
            return [PlexHomeUser(id: "protected", name: "Protected", requiresPIN: true)]
        }
        app.plexHomeUsers.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("A selection may not authenticate without a PIN.")
            throw CancellationError()
        }
        try await PerformanceProbe.measure(self, scenario: "mobile-profile-selection") {
            var selectionMicroseconds = 0
            var maxSelectionMicroseconds = 0
            for id in targets {
                let start = ContinuousClock.now
                app.selectProfile(id)
                let elapsed = start.duration(to: .now).components
                let microseconds = Int(elapsed.seconds) * 1_000_000 + Int(elapsed.attoseconds / 1_000_000_000_000)
                selectionMicroseconds += microseconds
                maxSelectionMicroseconds = max(maxSelectionMicroseconds, microseconds)
                XCTAssertEqual(app.profiles.activeProfileID, id)
                XCTAssertNotNil(app.plexHomeUsers.pendingPlexPINRequest)
                await app.plexHomeUsers.waitForPlexPINRequirementCheck()
                XCTAssertEqual(app.plexHomeUsers.plexPINEntryAvailability, .available)
                XCTAssertNil(app.accountsProviders.tokenResolver("profile-performance-plex"))
            }
            return [
                "selections": targets.count, "selectionMicroseconds": selectionMicroseconds,
                "maxSelectionMicroseconds": maxSelectionMicroseconds
            ]
        }
    }
}
#endif
