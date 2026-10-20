#if os(tvOS)
import AVFoundation
import CoreNetworking
import Foundation
import Observation
import SwiftUI

enum SystemPlaybackAudioSetting: Int, CaseIterable {
    case reduceLoudSounds = -100
    case enhanceDialogue = -101

    var title: LocalizedStringResource {
        switch self {
        case .reduceLoudSounds: "Reduce Loud Sounds"
        case .enhanceDialogue: "Enhance Dialogue"
        }
    }

    var availabilityKey: String {
        switch self {
        case .reduceLoudSounds: "lateNightModeIsAvailable"
        case .enhanceDialogue: "enhanceDialogIsAvailable"
        }
    }

    var enabledKey: String {
        switch self {
        case .reduceLoudSounds: "latenightmode"
        case .enhanceDialogue: "enhancedialog"
        }
    }

    func notification(enabled: Bool) -> Notification.Name {
        switch (self, enabled) {
        case (.reduceLoudSounds, true): .init("com.apple.TVPAudioVideoSettings.enableLateNightMode")
        case (.reduceLoudSounds, false): .init("com.apple.TVPAudioVideoSettings.disableLateNightMode")
        case (.enhanceDialogue, true): .init("com.apple.TVPAudioVideoSettings.enableEnhanceDialog")
        case (.enhanceDialogue, false): .init("com.apple.TVPAudioVideoSettings.disableEnhanceDialog")
        }
    }
}

@MainActor
protocol SystemPlaybackAudioControlling {
    func read() -> [SystemPlaybackAudioSetting: Bool]
    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) throws
}

/// Undocumented tvOS integration: the system owns availability, processing and
/// persistence. Never write the preference domain or mirror it in profile state.
@MainActor
struct SystemPlaybackAudioPreferences: SystemPlaybackAudioControlling {
    private let domain = "com.apple.preferences-sounds" as CFString

    private var notificationCenter: NotificationCenter? {
        (NSClassFromString("NSDistributedNotificationCenter") as? NotificationCenter.Type)?.default
    }

    func read() -> [SystemPlaybackAudioSetting: Bool] {
        CFPreferencesAppSynchronize(domain)
        return Self.availableValues(canPost: notificationCenter != nil) { key in
            CFPreferencesGetAppBooleanValue(key as CFString, domain, nil)
        }
    }

    static func availableValues(
        canPost: Bool, readBoolean: (String) -> Bool
    ) -> [SystemPlaybackAudioSetting: Bool] {
        guard canPost else { return [:] }
        var values: [SystemPlaybackAudioSetting: Bool] = [:]
        for setting in SystemPlaybackAudioSetting.allCases where readBoolean(setting.availabilityKey) {
            values[setting] = readBoolean(setting.enabledKey)
        }
        return values
    }

    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) throws {
        guard let center = notificationCenter, read()[setting] != nil else {
            throw SystemPlaybackAudio.Failure.unavailable
        }
        center.post(name: setting.notification(enabled: enabled), object: nil)
    }
}

@MainActor @Observable
final class SystemPlaybackAudio {
    enum Failure: Error {
        case unavailable
        case unconfirmed
    }

    static let shared = SystemPlaybackAudio(backend: SystemPlaybackAudioPreferences())

    private let backend: any SystemPlaybackAudioControlling
    private(set) var values: [SystemPlaybackAudioSetting: Bool]
    private(set) var pending: Set<SystemPlaybackAudioSetting> = []
    var failure: Failure?

    init(backend: any SystemPlaybackAudioControlling) {
        self.backend = backend
        values = backend.read()
    }

    var availableSettings: [SystemPlaybackAudioSetting] {
        SystemPlaybackAudioSetting.allCases.filter { values[$0] != nil }
    }

    func refresh() {
        let latest = backend.read()
        if latest != values { values = latest }
    }

    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) async {
        guard !pending.contains(setting) else { return }
        failure = nil
        refresh()
        guard let current = values[setting] else {
            report(.unavailable)
            return
        }
        guard current != enabled else { return }
        pending.insert(setting)
        defer { pending.remove(setting) }
        do {
            try Task.checkCancellation()
            try backend.setEnabled(enabled, for: setting)
            // Posting is not acknowledgement. Keep the real checkmark until the
            // system confirms, including when the output changes during the wait.
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100))
                refresh()
                guard let current = values[setting] else {
                    report(.unavailable)
                    return
                }
                if current == enabled { return }
            }
            report(.unconfirmed)
        } catch is CancellationError {
            refresh()
            PlozzLog.playback.debug("System audio setting confirmation was cancelled.")
        } catch {
            report(.unavailable)
        }
    }

    private func report(_ failure: Failure) {
        self.failure = failure
        PlozzLog.playback.error("System audio setting change failed: \(String(describing: failure))")
    }
}

/// Refresh only while transport controls are visible. The system does not offer
/// a public preference-change notification for changes made in Control Center.
private struct SystemPlaybackAudioObservation: ViewModifier {
    let audio: SystemPlaybackAudio
    let isVisible: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var isActive: Bool { isVisible && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
                if isActive { audio.refresh() }
            }
            .task(id: isActive) {
                guard isActive else { return }
                do {
                    while !Task.isCancelled {
                        audio.refresh()
                        try await Task.sleep(for: .seconds(1))
                    }
                } catch is CancellationError {
                    // SwiftUI cancels the visible-controls lifetime.
                } catch {
                    PlozzLog.playback.error("System audio setting refresh timer failed.")
                }
            }
    }
}

extension View {
    func observingSystemPlaybackAudio(_ audio: SystemPlaybackAudio, isVisible: Bool) -> some View {
        modifier(SystemPlaybackAudioObservation(audio: audio, isVisible: isVisible))
    }
}
#endif
