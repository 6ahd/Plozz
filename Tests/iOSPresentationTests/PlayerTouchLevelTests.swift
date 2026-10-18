import CoreModels
import MediaPlayer
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchLevelTests: XCTestCase {
    func testSettingsDefaultUpgradeRoundTripAndProfileIsolation() throws {
        XCTAssertTrue(PlaybackSettings.default.volumeBrightnessGestures)
        let legacy = try JSONDecoder().decode(PlaybackSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.volumeBrightnessGestures)
        let suite = "PlayerTouchLevelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let primary = PlaybackSettingsStore(defaults: defaults)
        let guest = PlaybackSettingsStore(defaults: defaults, namespace: "guest")
        let model = PlaybackSettingsModel(store: guest)
        model.settings.volumeBrightnessGestures = false
        XCTAssertFalse(guest.load().volumeBrightnessGestures)
        XCTAssertTrue(primary.load().volumeBrightnessGestures)
        XCTAssertEqual(guest.load(), model.settings)
    }

    func testSwipeZonesKeepCenterNeutralAndValuesAreRelativeAndBounded() {
        XCTAssertEqual(PlayerTouchLevelDrag.kind(at: 180, width: 1000), .brightness)
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: 500, width: 1000))
        XCTAssertEqual(PlayerTouchLevelDrag.kind(at: 820, width: 1000), .volume)
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: -1, width: 1000))
        XCTAssertNil(PlayerTouchLevelDrag.kind(at: 0, width: 0))
        let drag = PlayerTouchLevelDrag(kind: .volume, startValue: 0.5, height: 800)
        XCTAssertEqual(drag.value(translationY: -160), 0.7)
        XCTAssertEqual(drag.value(translationY: 240), 0.2)
        XCTAssertEqual(drag.value(translationY: -1000), 1)
        XCTAssertEqual(drag.value(translationY: 1000), 0)
        XCTAssertNil(drag.value(translationY: .nan))
    }

    func testLevelFeedbackReplacesSkippingAndCancellationClearsIt() async throws {
        let state = PlayerTouchGestureState()
        defer { state.cancel() }
        _ = state.seek(by: 10, from: 20, within: 0...100)
        state.showLevel(.brightness, value: 0.4)
        XCTAssertNil(state.skip)
        XCTAssertEqual(state.level?.value, 0.4)
        XCTAssertTrue(state.isActive)
        state.finishLevel()
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertNil(state.level)
        state.showLevel(.volume, value: nil)
        XCTAssertNil(state.level?.value)
        XCTAssertTrue(state.isActive, "Unavailable output still needs visible feedback.")
        state.cancel()
        XCTAssertFalse(state.isActive)
    }

    func testBrightnessRestoresOnTeardownButDoesNotOverwriteAnExternalChange() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        // Simulator brightness is fixed at 0.5. Exercise ownership at the native
        // read/write boundary instead of claiming a simulated backlight changed.
        var brightness: CGFloat = 0.6
        var writes: [CGFloat] = []
        let control = PlayerTouchLevelControl(
            readBrightness: { _ in brightness },
            writeBrightness: { _, value in brightness = value; writes.append(value) }
        )
        let original = brightness
        defer {
            control.deactivate()
            window.isHidden = true
        }
        XCTAssertEqual(try control.begin(.brightness, in: host.view), Double(original))
        try control.set(.brightness, value: 0.27, in: host.view)
        XCTAssertEqual(brightness, 0.27, accuracy: 0.01)
        control.deactivate()
        XCTAssertEqual(brightness, original, accuracy: 0.01)
        _ = try control.begin(.brightness, in: host.view)
        try control.set(.brightness, value: 0.4, in: host.view)
        brightness = 0.8
        control.deactivate()
        XCTAssertEqual(brightness, 0.8, accuracy: 0.01)
        XCTAssertEqual(writes, [0.27, original, 0.4])
    }

    func testVolumeBridgeIsRemovedOnTeardownAndMissingWindowIsExplicitlyUnavailable() throws {
        let control = PlayerTouchLevelControl()
        XCTAssertThrowsError(try control.begin(.volume, in: UIView()))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        defer {
            control.deactivate()
            window.isHidden = true
        }
        do {
            _ = try control.begin(.volume, in: host.view)
            XCTAssertEqual(host.view.subviews.filter { $0 is MPVolumeView }.count, 1)
        } catch PlayerTouchLevelControl.Failure.unavailable {
            XCTAssertFalse(host.view.subviews.contains { $0 is MPVolumeView })
        }
        control.deactivate()
        XCTAssertFalse(host.view.subviews.contains { $0 is MPVolumeView })
    }

    func testReplacingTheGestureSurfacePreservesBrightnessUntilPlaybackDeactivates() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.isHidden = false
        var brightness: CGFloat = 0.6
        let control = PlayerTouchLevelControl(
            readBrightness: { _ in brightness },
            writeBrightness: { _, value in brightness = value }
        )
        defer {
            control.deactivate()
            window.isHidden = true
        }
        let outgoing = PlayerTouchGestureSurface.Coordinator(surface(isActive: true), sharedLevelControl: control)
        outgoing.install(in: host.view)
        _ = try control.begin(.brightness, in: host.view)
        try control.set(.brightness, value: 0.25, in: host.view)
        PlayerTouchGestureSurface.dismantleUIView(host.view, coordinator: outgoing)
        XCTAssertEqual(brightness, 0.25, "An episode/engine handoff must not restore the old brightness.")

        let incoming = PlayerTouchGestureSurface.Coordinator(surface(isActive: true), sharedLevelControl: control)
        XCTAssertEqual(try control.begin(.brightness, in: host.view), 0.25)
        try control.set(.brightness, value: 0.35, in: host.view)
        incoming.update(surface(isActive: false))
        XCTAssertEqual(brightness, 0.6, "Leaving local foreground playback restores the session's original level.")
    }

    private func surface(isActive: Bool) -> PlayerTouchGestureSurface {
        PlayerTouchGestureSurface(
            state: PlayerTouchGestureState(), shortcutsEnabled: true,
            levelsEnabled: true, isActive: isActive,
            canSeek: true, canBoost: true, canZoom: true,
            onTap: { XCTFail("A lifecycle change must not tap the player.") },
            onSkip: { _ in XCTFail("A lifecycle change must not seek.") },
            onBoostChanged: { _ in XCTFail("No hold gesture is active.") },
            onZoom: { _ in XCTFail("A lifecycle change must not zoom.") },
            onGestureStarted: { XCTFail("A lifecycle change must not begin a gesture.") }
        )
    }
}
