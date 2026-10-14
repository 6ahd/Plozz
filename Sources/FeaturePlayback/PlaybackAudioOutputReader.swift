#if canImport(AVFoundation)
import AVFoundation
import CoreModels
import Foundation

@MainActor
enum PlaybackAudioOutputReader {
    static func read() -> PlaybackDiagnostics.AudioOutput? {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        return facts(renderingMode: session.renderingMode, ports: session.currentRoute.outputs.map(\.portType))
        #else
        return nil
        #endif
    }

    #if os(iOS) || os(tvOS)
    static func facts(
        renderingMode: AVAudioSession.RenderingMode, ports: [AVAudioSession.Port]
    ) -> PlaybackDiagnostics.AudioOutput? {
        guard !ports.isEmpty else { return nil }
        var connections: [LocalizedStringResource] = []
        for port in ports {
            if let label = connection(port), !connections.contains(label) {
                connections.append(label)
            }
        }
        let mode: LocalizedStringResource?
        switch renderingMode {
        case .notApplicable: mode = nil
        case .monoStereo: mode = "Mono / Stereo"
        case .surround: mode = "Surround"
        case .spatialAudio: mode = "Spatial Audio"
        case .dolbyAudio: mode = "Dolby Audio"
        case .dolbyAtmos: mode = "Dolby Atmos"
        @unknown default: mode = nil
        }
        guard mode != nil || !connections.isEmpty else { return nil }
        return .init(renderingMode: mode, connections: connections)
    }

    private static func connection(_ port: AVAudioSession.Port) -> LocalizedStringResource? {
        // Port names and UIDs can contain personal device names. Only fixed types
        // cross this boundary; channel counts cannot establish Atmos or speakers.
        switch port {
        case .HDMI: "HDMI"
        case .airPlay: "AirPlay"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: "Bluetooth"
        case .headphones: "Headphones"
        case .builtInSpeaker: "Built-in speakers"
        case .builtInReceiver: "Built-in receiver"
        case .usbAudio: "USB"
        case .lineOut: "Line out"
        case .carAudio: "Car audio"
        case .displayPort: "DisplayPort"
        case .thunderbolt: "Thunderbolt"
        case .fireWire: "FireWire"
        case .AVB: "AVB"
        case .PCI: "PCI"
        case .virtual: "Virtual audio"
        default: nil
        }
    }
    #endif
}
#endif
