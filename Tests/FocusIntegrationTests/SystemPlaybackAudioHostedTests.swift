import AVFoundation
@testable import CoreUI
@testable import FeaturePlayback
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class SystemPlaybackAudioHostedTests: XCTestCase {
    func testSystemRowsKeepNativeFocusThroughConfirmationAndRouteChanges() async throws {
        try await withPanel { probe, window in
            try self.assertFocused("Reduce Loud Sounds", in: window)
            let initialFrame = try self.focusFrame(in: window)
            XCTAssertTrue(LiveChannelOverlay.showsAudio(trackCount: 1, systemAudio: probe.model.systemAudio))
            let rows = PlayerOptionsPanel.audioRows(model: probe.model, actions: PlayerOptionsActions())
            rows[0].action()
            try await self.waitUntil {
                probe.model.systemAudio.values[.reduceLoudSounds] == true && probe.model.systemAudio.pending.isEmpty
            }
            XCTAssertEqual(probe.backend.writes, 1)
            XCTAssertEqual(try self.focusFrame(in: window), initialFrame)
            try self.assertFocused("Reduce Loud Sounds", in: window)

            probe.requestedFocus = .row(-101)
            try await self.waitUntil { probe.focus == .row(-101) }
            try self.assertFocused("Enhance Dialogue", in: window)
            probe.backend.values = [.reduceLoudSounds: true]
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
            try await self.waitUntil { probe.focus == .row(-100) }
            try self.assertFocused("Reduce Loud Sounds", in: window)
            XCTAssertEqual(probe.backend.writes, 1, "Route changes must only read the system.")
            let attachment = XCTAttachment(image: DetailTransitionSnapshot.image(of: window))
            attachment.name = "System audio output availability preserves native focus"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            probe.backend.values = [:]
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
            try await self.waitUntil { probe.focus == .subBack }
            try self.assertFocused("Back", in: window)
            probe.backend.values = [.enhanceDialogue: false]
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
            try await self.waitUntil { probe.focus == .row(-101) }
            try self.assertFocused("Enhance Dialogue", in: window)
            XCTAssertEqual(probe.backend.writes, 1)
        }
    }

    func testSystemRefreshStopsWhenHiddenAndResumesOnForeground() async throws {
        try await withPanel { probe, _ in
            probe.visible = false
            try await self.waitUntil { !probe.observationActive }
            let readsWhenHidden = probe.backend.reads
            probe.backend.values[.enhanceDialogue] = true
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
            try await Task.sleep(for: .milliseconds(1_200))
            XCTAssertEqual(probe.backend.reads, readsWhenHidden)
            XCTAssertEqual(probe.model.systemAudio.values[.enhanceDialogue], false)

            probe.visible = true
            try await self.waitUntil { probe.model.systemAudio.values[.enhanceDialogue] == true }
            probe.phase = .background
            try await self.waitUntil { !probe.observationActive }
            let readsInBackground = probe.backend.reads
            probe.backend.values[.enhanceDialogue] = false
            NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil)
            try await Task.sleep(for: .milliseconds(1_200))
            XCTAssertEqual(probe.backend.reads, readsInBackground)
            XCTAssertEqual(probe.model.systemAudio.values[.enhanceDialogue], true)

            probe.phase = .active
            try await self.waitUntil { probe.model.systemAudio.values[.enhanceDialogue] == false }
            XCTAssertEqual(probe.backend.writes, 0)
        }
    }

    func testRefusedSystemChangeShowsAnAlertWithoutChangingSelection() async throws {
        try await withPanel { probe, window in
            probe.backend.acknowledgesChanges = false
            PlayerOptionsPanel.audioRows(model: probe.model, actions: PlayerOptionsActions())[0].action()
            try await self.waitUntil { probe.model.systemAudio.failure == .unconfirmed }
            try await self.waitUntil { window.rootViewController?.presentedViewController != nil }
            let alert = try XCTUnwrap(window.rootViewController?.presentedViewController)
            try await self.waitUntil { !alert.isBeingPresented }
            XCTAssertEqual(probe.model.systemAudio.values[.reduceLoudSounds], false)
            let image = DetailTransitionSnapshot.image(of: window)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains("audio setting"), text)
            XCTAssertTrue(text.contains("Apple TV Settings"), text)
            probe.model.systemAudio.failure = nil
            try await self.waitUntil { window.rootViewController?.presentedViewController == nil }
        }
    }

    @MainActor
    final class Backend: SystemPlaybackAudioControlling {
        var values: [SystemPlaybackAudioSetting: Bool] = [.reduceLoudSounds: false, .enhanceDialogue: false]
        var writes = 0
        var reads = 0
        var acknowledgesChanges = true

        func read() -> [SystemPlaybackAudioSetting: Bool] {
            reads += 1
            return values
        }

        func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) {
            writes += 1
            if acknowledgesChanges { values[setting] = enabled }
        }
    }

    @MainActor @Observable
    final class Probe {
        let backend = Backend()
        let model: PlayerControlsModel
        var requestedFocus: PlayerControls.FocusSlot = .row(-100)
        var focus: PlayerControls.FocusSlot?
        var visible = true
        var phase = ScenePhase.active
        var observationActive = true

        init() {
            model = PlayerControlsModel(systemAudio: SystemPlaybackAudio(backend: backend))
        }
    }

    private struct Panel: View {
        let probe: Probe
        @State private var heights: [PlayerControls.Category: CGFloat] = [:]
        @FocusState private var focus: PlayerControls.FocusSlot?

        var body: some View {
            PlayerOptionsPanel(
                category: .audio, model: probe.model, palette: .dark, actions: PlayerOptionsActions(),
                subtitleScreen: .constant(.tracks), heightCache: $heights, focus: $focus,
                close: {}, backRequest: 0, maximumHeight: 900
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(60)
            .background(.black)
            .observingSystemPlaybackAudio(probe.model.systemAudio, isVisible: probe.visible)
            .environment(\.scenePhase, probe.phase)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark)
            .onChange(of: probe.requestedFocus) { _, value in focus = value }
            .onChange(of: focus) { _, value in probe.focus = value }
            .onChange(of: probe.visible && probe.phase == .active) { _, value in probe.observationActive = value }
        }
    }

    private func withPanel(_ body: (Probe, UIWindow) async throws -> Void) async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let probe = Probe()
        window.rootViewController = UIHostingController(rootView: Panel(probe: probe))
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await waitUntil { probe.focus == .row(-100) && UIFocusSystem.focusSystem(for: window)?.focusedItem != nil }
        try await body(probe, window)
    }

    private func focusFrame(in window: UIWindow) throws -> CGRect {
        let item = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
        var environment: (any UIFocusEnvironment)? = item
        while let current = environment {
            if let container = current.focusItemContainer {
                return container.coordinateSpace.convert(item.frame, to: window)
            }
            environment = current.parentFocusEnvironment
        }
        return try XCTUnwrap(nil as CGRect?, "The focused row must have a coordinate space.")
    }

    private func assertFocused(_ expected: String, in window: UIWindow) throws {
        let frame = try focusFrame(in: window)
        XCTAssertLessThan(frame.height, 120)
        let image = DetailTransitionSnapshot.image(of: window)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        XCTAssertTrue((request.results ?? []).contains {
            ($0.topCandidates(1).first?.string.contains(expected) == true)
                && frame.contains(CGPoint(x: $0.boundingBox.midX * window.bounds.width,
                                          y: (1 - $0.boundingBox.midY) * window.bounds.height))
        }, "The native focused row must contain \(expected).")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}
