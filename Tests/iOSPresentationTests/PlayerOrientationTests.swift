import CoreModels
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class PlayerOrientationTests: XCTestCase {
    func testCloseDismissesOwnedControllerWithoutAnotherPresenterUpdate() async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let anchor = PlozziOSPlayerPresentation<Color>.Anchor()
        let coordinator = PlozziOSPlayerPresentation<Color>.Coordinator()
        var request: PlozziOSPlaybackRequest? = PlayerCloseProbe.makeRequest()
        var disappearances = 0
        coordinator.anchor = anchor
        coordinator.request = request
        coordinator.makeContent = { _, _ in AnyView(Color.black.onDisappear { disappearances += 1 }) }
        coordinator.clearRequest = { id in
            if request?.id == id { request = nil }
        }
        window.rootViewController = anchor
        window.makeKeyAndVisible()
        defer {
            anchor.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(500))
        let player = try XCTUnwrap(coordinator.host)
        XCTAssertTrue(anchor.presentedViewController === player)
        player.orientation.close()
        XCTAssertNil(request, "The parent's request is cleared.")
        let deadline = ContinuousClock.now + .seconds(2)
        while (coordinator.host != nil || disappearances < 1), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNil(coordinator.host, "Close must dismiss UIKit without waiting for an offscreen SwiftUI update.")
        XCTAssertNil(anchor.presentedViewController)
        XCTAssertNil(player.orientation.host)
        XCTAssertEqual(disappearances, 1, "Dismissal must run the player's cleanup lifecycle.")
        guard coordinator.host == nil else { return }

        request = PlayerCloseProbe.makeRequest()
        coordinator.request = request
        coordinator.reconcile()
        try await Task.sleep(for: .milliseconds(500))
        let replacement = try XCTUnwrap(coordinator.host)
        let replacementID = request?.id
        player.orientation.close()
        XCTAssertEqual(request?.id, replacementID)
        XCTAssertTrue(coordinator.host === replacement, "A stale X must not dismiss the replacement player.")
        replacement.orientation.close()
        let replacementDeadline = ContinuousClock.now + .seconds(2)
        while (coordinator.host != nil || disappearances < 2), ContinuousClock.now < replacementDeadline {
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNil(coordinator.host)
        XCTAssertEqual(disappearances, 2)
    }

    func testCloseDoesNotDependOnPresentingViewUpdatesAndAllowsReopening() async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let probe = PlayerCloseProbe()
        let host = UIHostingController(rootView: PlayerCloseFixture(probe: probe))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while (probe.appearances == 0 || host.presentedViewController != nil || probe.orientation?.host != nil),
              ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertGreaterThan(probe.appearances, 0, "The real UIKit cover must have appeared.")
        XCTAssertNil(probe.request, "Close must clear the request.")
        XCTAssertNil(host.presentedViewController, "An early close must not be lost during the presentation animation.")
        XCTAssertNil(probe.orientation?.host, "Close must release the player's presentation owner.")
        guard host.presentedViewController == nil, probe.orientation?.host == nil else { return }

        let oldOrientation = probe.orientation
        probe.closesOnAppear = false
        probe.request = PlayerCloseProbe.makeRequest()
        host.rootView = PlayerCloseFixture(probe: probe, generation: 1)
        let reopenDeadline = ContinuousClock.now + .seconds(3)
        while (host.presentedViewController == nil || probe.appearances < 2), ContinuousClock.now < reopenDeadline {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNotNil(host.presentedViewController, "Closing must not prevent another player from opening.")
        XCTAssertEqual(probe.appearances, 2)
        try await Task.sleep(for: .milliseconds(400))
        let reopenedRequest = probe.request?.id
        oldOrientation?.close()
        XCTAssertEqual(probe.request?.id, reopenedRequest, "An old close action must not clear a newer player.")
        XCTAssertNotNil(host.presentedViewController)
        probe.orientation?.close()
        let closeDeadline = ContinuousClock.now + .seconds(3)
        while host.presentedViewController != nil, ContinuousClock.now < closeDeadline {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(16))
        }
        XCTAssertNil(host.presentedViewController)
    }

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

    func testIPadsAndWindowedPresentationsStayAutomatic() {
        let screen = CGSize(width: 1024, height: 1366)
        XCTAssertFalse(PlozziOSPlayerOrientation.supportsPreference(
            idiom: .pad, windowSize: screen, screenSize: screen
        ))
        XCTAssertFalse(PlozziOSPlayerOrientation.supportsPreference(
            idiom: .pad, windowSize: CGSize(width: 500, height: 1366), screenSize: screen
        ))
        XCTAssertFalse(PlozziOSPlayerOrientation.supportsPreference(
            idiom: .phone, windowSize: CGSize(width: 500, height: 1366), screenSize: screen
        ))
        XCTAssertTrue(PlozziOSPlayerOrientation.supportsPreference(
            idiom: .phone,
            windowSize: CGSize(width: 1366, height: 1024), screenSize: screen
        ))
        XCTAssertTrue(PlozziOSPlayerOrientation.supportsPreference(
            idiom: .phone, windowSize: screen, screenSize: screen
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
        XCTAssertFalse(PlozziOSPlayerOrientation(preference: .landscape).hasGeometryRequestFailed)
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

@MainActor
private final class PlayerCloseProbe {
    var request: PlozziOSPlaybackRequest? = makeRequest()
    var orientation: PlozziOSPlayerOrientation?
    var appearances = 0
    var closesOnAppear = true

    static func makeRequest() -> PlozziOSPlaybackRequest {
        .init(
            item: .init(id: "close-fixture", title: "Fixture", kind: .movie),
            startPosition: 0, versionPreferences: VersionPreferenceStore(namespace: "close-fixture")
        )
    }
}

private struct PlayerCloseFixture: View {
    let probe: PlayerCloseProbe
    var generation = 0

    var body: some View {
        Text("Presenter \(generation)")
            .plozziOSPlayerCover(item: Binding(
                get: { probe.request }, set: { probe.request = $0 }
            ), orientation: .auto) { _, orientation in
                Color.black
                    .background(PlayerCloseAttachment {
                        probe.orientation = orientation
                        probe.appearances += 1
                        if probe.closesOnAppear { orientation.close() }
                    })
            }
    }
}

private struct PlayerCloseAttachment: UIViewRepresentable {
    let attached: () -> Void

    func makeUIView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.attached = attached
        return view
    }

    func updateUIView(_ view: AttachmentView, context: Context) {}

    final class AttachmentView: UIView {
        var attached: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let attached else { return }
            self.attached = nil
            attached()
        }
    }
}
