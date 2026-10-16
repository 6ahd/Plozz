#if os(iOS)
import CoreModels
import FeatureAuth
import SwiftUI
import UIKit
import XCTest
@testable import AppRuntime
@testable import AppShelliOS

@MainActor
final class PlexPINPresentationTests: XCTestCase {
    func testUnresolvedDefaultProfilePINDisallowsInteractiveSheetDismissal() async throws {
        let suite = "PlexPINPresentationTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = ProfilesModel(store: ProfileStore(defaults: defaults))
        let accounts = AccountStore(secureStore: InMemorySecureStore())
        try accounts.add(Account(
            id: "plex", server: MediaServer(
                id: "server", name: "Fixture", baseURL: URL(string: "https://plex.example")!, provider: .plex
            ), userID: "owner", userName: "Owner", deviceID: "fixture"
        ), token: "FIXTURE-ADMIN")
        let hub = AccountsProvidersModel(
            accountStore: accounts, registry: ProviderRegistry(), profilesModel: profiles
        )
        hub.reloadAccounts()
        let model = PlexHomeUsersModel(
            accountsProviders: hub, profilesModel: profiles,
            plexHomeUserTokenCache: PlexHomeUserTokenCache(store: InMemorySecureStore()),
            automaticSignInStore: AutomaticSignInStore(defaults: defaults, secureStore: InMemorySecureStore()),
            switchProfile: { _ in XCTFail("The default profile has no alternate fallback.") }
        )
        model.plexHomeUsersFetch = { _, _ in
            [PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)]
        }
        model.plexHomeUserSwitch = { _, _, _, _ in
            XCTFail("The PIN sheet must remain even if an owner-authorized switch would succeed.")
            return "UNVERIFIED-CLOUD"
        }
        model.setPlexHomeUserForActiveProfile(
            accountID: "plex", user: PlexHomeUser(id: "parent", name: "Parent", requiresPIN: true)
        )
        await model.waitForPlexPINRequirementCheck()
        let request = try XCTUnwrap(model.pendingPlexPINRequest)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView:
            Color.clear.sheet(item: Binding(
                get: { model.pendingPlexPINRequest },
                set: { if $0 == nil { model.dismissPlexPINIfPresented() } }
            )) { request in
                PlozziOSPlexPINView(model: model, request: request)
                    .environment(\.locale, Locale(identifier: "en"))
            }
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil(window) { host.presentedViewController?.view.window != nil }
        let presented = try XCTUnwrap(host.presentedViewController)
        let presentation = try XCTUnwrap(presented.presentationController)
        try await waitUntil(window) {
            presented.isModalInPresentation
                || presentation.delegate?.presentationControllerShouldDismiss?(presentation) == false
        }
        presentation.delegate?.presentationControllerDidAttemptToDismiss?(presentation)
        XCTAssertEqual(model.pendingPlexPINRequest, request)

        model.cancelPlexPIN()
        let observationEnd = ContinuousClock.now + .milliseconds(500)
        repeat {
            XCTAssertEqual(model.pendingPlexPINRequest, request)
            XCTAssertTrue(host.presentedViewController === presented)
            XCTAssertFalse(presented.isBeingDismissed)
            XCTAssertFalse(model.isSubmittingPlexPIN)
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < observationEnd

    }

    private func waitUntil(
        _ window: UIWindow, file: StaticString = #filePath, line: UInt = #line,
        _ predicate: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            window.layoutIfNeeded()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        XCTFail("The PIN presentation did not reach its expected state.", file: file, line: line)
        throw PresentationError.timedOut
    }

    private enum PresentationError: Error { case timedOut }
}
#endif
