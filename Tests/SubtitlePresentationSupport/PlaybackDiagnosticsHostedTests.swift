import CoreModels
import CoreUI
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlaybackDiagnosticsHostedTests: XCTestCase {
    func testAvailableSpaceClearsCardsTabsAndMenusInTheSameCoordinateSpace() {
        let bounds = CGRect(x: 40, y: 30, width: 1920, height: 1080)
        for top: CGFloat in [650, 420, 60] {
            let controls = CGRect(x: 80, y: top, width: 1800, height: 400)
            let space = TelevisionDiagnosticsPlacement<EmptyView>.availableRect(in: bounds, avoiding: [controls])
            XCTAssertEqual(space.minX, 88)
            XCTAssertEqual(space.minY, 62)
            XCTAssertTrue(space.isEmpty || !space.intersects(controls))
            if space.height > 0 { XCTAssertLessThanOrEqual(space.maxY, top - 24) }
        }
        let unobstructed = TelevisionDiagnosticsPlacement<EmptyView>.availableRect(
            in: bounds, avoiding: [.null, CGRect(x: 3000, y: 0, width: 100, height: 100)]
        )
        XCTAssertEqual(unobstructed, bounds.insetBy(dx: 48, dy: 32))
    }

    #if os(tvOS)
    func testFullDiagnosticsClearRealTransportAndInfoCardWithoutShrinkingText() async throws {
        let scene = try await activeScene()
        let previous = scene.windows.first(where: \.isKeyWindow)
        let model = PlayerControlsModel()
        model.title = "Diagnostics layout fixture"
        model.infoCard.headline = "Visible Info card"
        model.infoCard.overview = "The full diagnostic panel must clear this card and its Info and Cast tabs."
        let measurement = PanelMeasurement()
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let diagnostics = PlaybackDiagnosticsOverlay(diagnostics: fixture)
        let panel = UIHostingController(rootView:
            TelevisionDiagnosticsPlacement(controlsLayout: model.subtitleLayout) { width in
                diagnostics.televisionPanel(width: width)
                    .environment(\.themePalette, .dark)
                    .reportSubtitleControlsFrame { measurement.frame = $0 }
            }
        )
        let controls = UIHostingController(rootView: PlayerControls(
            model: model, palette: .dark, actions: PlayerOptionsActions(), onExitToSurface: {}
        ).transaction { $0.disablesAnimations = true; $0.animation = nil })
        for host in [panel as UIViewController, controls as UIViewController] {
            root.addChild(host)
            host.view.frame = root.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.backgroundColor = .clear
            root.view.addSubview(host.view)
            host.didMove(toParent: root)
        }
        panel.safeAreaRegions = []
        controls.safeAreaRegions = []
        for info in [false, true] {
            model.controlsVisible = true
            model.controlBar.entry = info ? .info : .trackControls
            model.controlBarVisible = true
            try await waitUntil {
                window.layoutIfNeeded()
                let controlFrame = model.subtitleLayout.frame(for: info ? .card : .transport)
                guard controlFrame != nil, let frame = measurement.frame else { return false }
                return frame.height > 100 && model.subtitleLayout.frames.allSatisfy {
                    !frame.intersects($0) && frame.maxY <= $0.minY - 23
                }
            }
            let frame = try XCTUnwrap(measurement.frame)
            XCTAssertGreaterThan(frame.width, 1400, "Use the TV width instead of the old narrow, tall panel")
            XCTAssertLessThan(frame.height, 580, "All sections should fit above the Info card")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            for token in ["APAC", "7.1.4", "HDMI", "Thermal", "engines 2"] {
                XCTAssertTrue(text.contains(token), "The complete panel must be visible, including its last row: \(text)")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = info ? "Diagnostics above Info card" : "Diagnostics above transport"
            attachment.lifetime = .keepAlways
            add(attachment)
            model.controlBarVisible = false
            model.controlsVisible = false
            try await waitUntil { model.subtitleLayout.frames.isEmpty }
        }
        try await waitUntil { measurement.frame != nil }
        model.subtitleLayout.setFrame(CGRect(x: 0, y: 100, width: 1920, height: 980), for: .menu)
        try await waitUntil { measurement.frame == nil }
        model.subtitleLayout.setFrame(nil, for: .menu)
        try await waitUntil { measurement.frame != nil }
    }

    private var fixture: PlaybackDiagnostics {
        var value = PlaybackDiagnostics(
            resolution: .init(width: 3840, height: 2160), videoCodec: "HEVC", videoBitrate: 29_000_000,
            audioCodec: "Dolby Atmos", audioChannels: 8, audioSampleRate: 48_000, audioBitrate: 4_200_000,
            audioPipelineDescription: "TRUEHD Atmos → APAC 7.1.4",
            audioOutput: .init(renderingMode: "Dolby Atmos", connections: ["HDMI"]),
            subtitleDescription: "SubRip · English", container: "mkv", mode: .plozzigen,
            hdr: .dolbyVision, engineName: "Plozzigen", bufferedSecondsAhead: 10, engineBufferedSecondsAhead: 45,
            stallCount: 0, droppedVideoFrames: 0, frameRate: 24,
            deviceModel: "Apple TV 4K (2nd gen)", deviceMemoryBytes: 3_000_000_000,
            freeDiskBytes: 600_000_000, totalDiskBytes: 32_000_000_000,
            memoryFootprintBytes: 950_000_000, thermalState: .nominal, liveViewModels: 1, liveNativeEngines: 2,
            sourceFileName: String(repeating: "A long media filename [2160p][Dolby Vision][TrueHD Atmos 7.1] ", count: 5) + ".mkv",
            sourceFileSizeBytes: 28_000_000_000, dolbyVisionProfile: 8, colorTransfer: "smpte2084",
            videoRangeType: "DOVIWITHHDR10", durationSeconds: 7488, positionSeconds: 87,
            seekableStartSeconds: 0, seekableEndSeconds: 7488, playbackState: "Ready · Playing"
        )
        value.sourceProvider = .plex
        value.serverName = "Fixture server"
        value.streamTransport = PlaybackDiagnostics.streamTransportFacts(url: URL(string: "http://127.0.0.1:12345/master.m3u8"))
        return value
    }

    private func activeScene() async throws -> UIWindowScene {
        try await waitUntil { UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive } }
        return try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
            $0.activationState == .foregroundActive
        })
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "Diagnostics and control geometry did not settle")
    }
    #endif
}

@MainActor
@Observable
private final class PanelMeasurement {
    var frame: CGRect?
}
