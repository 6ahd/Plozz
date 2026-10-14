#if os(iOS) || os(tvOS)
import AVFoundation
import CoreModels
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlaybackAudioOutputTests: XCTestCase {
    func testRenderingModesComeOnlyFromTheSystemAndNotFromChannelCounts() {
        let cases: [(AVAudioSession.RenderingMode, LocalizedStringResource?)] = [
            (.notApplicable, nil), (.monoStereo, "Mono / Stereo"), (.surround, "Surround"),
            (.spatialAudio, "Spatial Audio"), (.dolbyAudio, "Dolby Audio"), (.dolbyAtmos, "Dolby Atmos")
        ]
        for (mode, expected) in cases {
            let facts = PlaybackAudioOutputReader.facts(renderingMode: mode, ports: [.HDMI])
            XCTAssertEqual(facts?.renderingMode, expected)
            XCTAssertEqual(facts?.connections, ["HDMI"])
        }
        XCTAssertNil(PlaybackAudioOutputReader.facts(renderingMode: .dolbyAtmos, ports: []))
        XCTAssertNil(PlaybackAudioOutputReader.facts(
            renderingMode: .notApplicable, ports: [.init(rawValue: "unrecognized-private-device")]
        ))
    }

    func testConnectionsAreFixedLabelsWithNoDeviceNamesOrDuplicateBluetoothRows() {
        let facts = PlaybackAudioOutputReader.facts(renderingMode: .spatialAudio, ports: [
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .usbAudio, .headphones,
            .builtInSpeaker, .builtInReceiver, .lineOut, .init(rawValue: "private-device-name")
        ])
        XCTAssertEqual(facts?.connections, [
            "Bluetooth", "AirPlay", "USB", "Headphones", "Built-in speakers", "Built-in receiver", "Line out"
        ])
    }

    func testSystemOutputRefreshesAndClearsForEveryPlaybackMode() {
        for mode: PlaybackDiagnostics.PlaybackMode in [.plozzigen, .directPlay, .remux, .transcode] {
            var output: PlaybackDiagnostics.AudioOutput? = .init(renderingMode: "Dolby Atmos", connections: ["HDMI"])
            let sampler = PlaybackDiagnosticsSampler(audioOutputReader: { output })
            defer { sampler.stop() }
            sampler.start(player: nil, mode: mode, metadata: .init(
                audio: .init(codec: "truehd", profile: "Dolby Atmos", channels: 8)
            ))
            sampler.sampleTick()
            XCTAssertEqual(sampler.latest?.audioOutput, output)
            output = .init(renderingMode: "Mono / Stereo", connections: ["Bluetooth"])
            sampler.sampleTick()
            XCTAssertEqual(sampler.latest?.audioOutput, output, "A route change must replace the old Atmos output")
            output = .init(connections: ["AirPlay"])
            sampler.sampleTick()
            XCTAssertNil(sampler.latest?.audioOutput?.renderingMode)
            XCTAssertEqual(sampler.latest?.audioOutput?.connections, ["AirPlay"])
            output = nil
            sampler.sampleTick()
            XCTAssertNil(sampler.latest?.audioOutput, "No measurement must not fall back to source Atmos")
        }
    }

    func testHiddenDiagnosticsAndStoppedSessionsDoNotReadOrRetainSystemOutput() {
        var reads = 0
        let sampler = PlaybackDiagnosticsSampler(audioOutputReader: {
            reads += 1
            return .init(renderingMode: "Dolby Atmos", connections: ["HDMI"])
        })
        sampler.start(player: nil, mode: .plozzigen, includesSystemMetrics: false)
        sampler.sampleTick()
        XCTAssertEqual(reads, 0)
        sampler.setSystemMetricsEnabled(true)
        sampler.sampleTick()
        XCTAssertEqual(reads, 1)
        XCTAssertNotNil(sampler.latest?.audioOutput)
        sampler.setSystemMetricsEnabled(false)
        sampler.sampleTick()
        XCTAssertEqual(reads, 1)
        XCTAssertNil(sampler.latest?.audioOutput)
        sampler.setSystemMetricsEnabled(true)
        sampler.sampleTick()
        sampler.stop()
        XCTAssertNil(sampler.latest?.audioOutput)
        sampler.sampleTick()
        XCTAssertEqual(reads, 2)
    }
}
#endif
