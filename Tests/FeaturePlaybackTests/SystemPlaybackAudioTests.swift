import SwiftUI
import XCTest
@testable import FeaturePlayback

@MainActor
func controlsWithoutSystemAudio() -> PlayerControlsModel {
    #if os(tvOS)
    PlayerControlsModel(systemAudio: SystemPlaybackAudio(backend: SystemAudioTestBackend()))
    #else
    PlayerControlsModel()
    #endif
}

#if os(tvOS)
@MainActor
final class SystemAudioTestBackend: SystemPlaybackAudioControlling {
    var values: [SystemPlaybackAudioSetting: Bool] = [:]
    var writes: [(SystemPlaybackAudioSetting, Bool)] = []
    var onRead: (() -> Void)?
    var onSet: ((Bool, SystemPlaybackAudioSetting) throws -> Void)?

    func read() -> [SystemPlaybackAudioSetting: Bool] {
        onRead?()
        return values
    }

    func setEnabled(_ enabled: Bool, for setting: SystemPlaybackAudioSetting) throws {
        writes.append((setting, enabled))
        if let onSet {
            try onSet(enabled, setting)
        } else {
            values[setting] = enabled
        }
    }
}

@MainActor
final class SystemPlaybackAudioTests: XCTestCase {
    func testAvailabilityRequiresBothTheBridgeAndOutputSupport() {
        let preferences = [
            "lateNightModeIsAvailable": true, "latenightmode": true,
            "enhanceDialogIsAvailable": false, "enhancedialog": true
        ]
        XCTAssertEqual(SystemPlaybackAudioPreferences.availableValues(canPost: true) {
            preferences[$0] ?? false
        }, [.reduceLoudSounds: true])
        XCTAssertTrue(SystemPlaybackAudioPreferences.availableValues(canPost: false) { _ in
            XCTFail("An unavailable bridge must not offer controls.")
            return true
        }.isEmpty)
        XCTAssertTrue(SystemPlaybackAudioPreferences.availableValues(canPost: true) { _ in false }.isEmpty)
    }

    func testAvailableButUnsetPreferenceIsOffNotUnavailable() {
        XCTAssertEqual(SystemPlaybackAudioPreferences.availableValues(canPost: true) {
            $0 == "enhanceDialogIsAvailable"
        }, [.enhanceDialogue: false])
    }

    func testCommandsOnlyToggleTheTwoSystemEffects() {
        XCTAssertEqual(SystemPlaybackAudioSetting.reduceLoudSounds.notification(enabled: true).rawValue,
                       "com.apple.TVPAudioVideoSettings.enableLateNightMode")
        XCTAssertEqual(SystemPlaybackAudioSetting.reduceLoudSounds.notification(enabled: false).rawValue,
                       "com.apple.TVPAudioVideoSettings.disableLateNightMode")
        XCTAssertEqual(SystemPlaybackAudioSetting.enhanceDialogue.notification(enabled: true).rawValue,
                       "com.apple.TVPAudioVideoSettings.enableEnhanceDialog")
        XCTAssertEqual(SystemPlaybackAudioSetting.enhanceDialogue.notification(enabled: false).rawValue,
                       "com.apple.TVPAudioVideoSettings.disableEnhanceDialog")
    }

    func testInitializationAndExternalRefreshNeverWritePreferences() {
        let backend = SystemAudioTestBackend()
        backend.values = [.enhanceDialogue: true, .reduceLoudSounds: false]
        let audio = SystemPlaybackAudio(backend: backend)
        XCTAssertEqual(audio.availableSettings, [.reduceLoudSounds, .enhanceDialogue])
        backend.values = [.enhanceDialogue: false]
        audio.refresh()
        XCTAssertEqual(audio.values, [.enhanceDialogue: false])
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testPlayerInstancesShareSystemStateWithoutChangingEngineFlags() {
        let backend = SystemAudioTestBackend()
        let audio = SystemPlaybackAudio(backend: backend)
        let vod = PlayerControlsModel(systemAudio: audio)
        let live = PlayerControlsModel(systemAudio: audio)
        backend.values = [.enhanceDialogue: true]
        vod.systemAudio.refresh()
        XCTAssertEqual(live.systemAudio.values, [.enhanceDialogue: true])
        XCTAssertFalse(vod.dialogEnhanceEnabled)
        XCTAssertFalse(live.dialogEnhanceEnabled)
        XCTAssertTrue(vod.engineCapabilities.isEmpty)
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertTrue(PlayerControlsModel().systemAudio === PlayerControlsModel().systemAudio)
    }

    func testSystemOnlyRowsKeepAudioReachableForVODAndLive() {
        let backend = SystemAudioTestBackend()
        backend.values = [.reduceLoudSounds: false, .enhanceDialogue: false]
        let audio = SystemPlaybackAudio(backend: backend)
        let model = PlayerControlsModel(systemAudio: audio)
        for trackCount in 0...1 {
            model.audioOptions = trackCount == 0 ? [] : [.init(id: 42, title: Text("English"), isSelected: true)]
            XCTAssertTrue(model.hasAudioControls)
            XCTAssertEqual(model.trackControlCategories, [.audio])
            XCTAssertTrue(LiveChannelOverlay.showsAudio(trackCount: trackCount, systemAudio: audio))
            let rows = PlayerOptionsPanel.audioRows(model: model, actions: PlayerOptionsActions())
            XCTAssertEqual(rows.map(\.id), [-100, -101])
            XCTAssertTrue(rows.allSatisfy(\.isToggle))
            XCTAssertFalse(rows.contains(where: \.isSelected))
            XCTAssertEqual(PlayerOptionsPanel.preferredFocus(for: .audio, subtitleScreen: .tracks, model: model),
                           .row(-100))
        }
        backend.values = [:]
        audio.refresh()
        XCTAssertFalse(model.hasAudioControls)
        XCTAssertFalse(LiveChannelOverlay.showsAudio(trackCount: 1, systemAudio: audio))
        XCTAssertTrue(LiveChannelOverlay.showsAudio(trackCount: 2, systemAudio: audio))
        XCTAssertTrue(backend.writes.isEmpty)
    }

    func testTrackSelectionAndEngineEffectStaySeparateFromSystemEffects() {
        let backend = SystemAudioTestBackend()
        backend.values = [.enhanceDialogue: true]
        let audio = SystemPlaybackAudio(backend: backend)
        let model = PlayerControlsModel(systemAudio: audio)
        model.audioOptions = [
            .init(id: 12, title: Text("English"), isSelected: false),
            .init(id: 27, title: Text("French"), isSelected: true)
        ]
        model.engineCapabilities = [.dialogEnhance]
        var selections: [Int] = []
        var enhancements: [Bool] = []
        let rows = PlayerOptionsPanel.audioRows(model: model, actions: PlayerOptionsActions(
            selectAudio: { selections.append($0) }, setDialogEnhance: { enhancements.append($0) }
        ))
        XCTAssertEqual(rows.map(\.id), [0, 1, 2, -101])
        rows[0].action()
        rows[2].action()
        XCTAssertEqual(selections, [12])
        XCTAssertEqual(enhancements, [true])
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertEqual(PlayerOptionsPanel.selectedRowIndex(for: .audio, model: model), 1)
    }

    func testBothEffectsCanBeEnabledAndDisabledWithReadback() async {
        let backend = SystemAudioTestBackend()
        backend.values = [.reduceLoudSounds: false, .enhanceDialogue: false]
        let audio = SystemPlaybackAudio(backend: backend)
        for setting in SystemPlaybackAudioSetting.allCases {
            await audio.setEnabled(true, for: setting)
            XCTAssertEqual(audio.values[setting], true)
            await audio.setEnabled(false, for: setting)
            XCTAssertEqual(audio.values[setting], false)
            XCTAssertNil(audio.failure)
            XCTAssertTrue(audio.pending.isEmpty)
        }
        XCTAssertEqual(backend.writes.map(\.1), [true, false, true, false])
    }

    func testDelayedAcknowledgementKeepsActualStateAndIgnoresRepeatPresses() async throws {
        let backend = SystemAudioTestBackend()
        backend.values = [.enhanceDialogue: false]
        backend.onSet = { _, _ in }
        let audio = SystemPlaybackAudio(backend: backend)
        let change = Task { await audio.setEnabled(true, for: .enhanceDialogue) }
        defer { change.cancel() }
        let deadline = ContinuousClock.now + .seconds(1)
        while backend.writes.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(backend.writes.count, 1)
        XCTAssertTrue(audio.pending.contains(.enhanceDialogue))
        XCTAssertEqual(audio.values[.enhanceDialogue], false)
        await audio.setEnabled(true, for: .enhanceDialogue)
        XCTAssertEqual(backend.writes.count, 1)
        backend.values[.enhanceDialogue] = true
        await change.value
        XCTAssertEqual(audio.values[.enhanceDialogue], true)
        XCTAssertNil(audio.failure)
        XCTAssertTrue(audio.pending.isEmpty)
    }

    func testUnacknowledgedChangeSurfacesFailureWithoutOptimisticCheckmark() async {
        let backend = SystemAudioTestBackend()
        backend.values = [.reduceLoudSounds: false]
        backend.onSet = { _, _ in }
        let audio = SystemPlaybackAudio(backend: backend)
        await audio.setEnabled(true, for: .reduceLoudSounds)
        XCTAssertEqual(audio.failure, .unconfirmed)
        XCTAssertEqual(audio.values[.reduceLoudSounds], false)
        XCTAssertTrue(audio.pending.isEmpty)
    }

    func testUnsupportedOrRejectedChangesAreVisibleFailures() async {
        let backend = SystemAudioTestBackend()
        let audio = SystemPlaybackAudio(backend: backend)
        await audio.setEnabled(true, for: .enhanceDialogue)
        XCTAssertEqual(audio.failure, .unavailable)
        XCTAssertTrue(backend.writes.isEmpty)
        backend.values[.enhanceDialogue] = false
        backend.onSet = { _, _ in throw SystemPlaybackAudio.Failure.unavailable }
        await audio.setEnabled(true, for: .enhanceDialogue)
        XCTAssertEqual(audio.failure, .unavailable)
        XCTAssertEqual(audio.values[.enhanceDialogue], false)
        XCTAssertTrue(audio.pending.isEmpty)
    }

    func testRouteLossDuringAcknowledgementDoesNotClaimSuccess() async {
        let backend = SystemAudioTestBackend()
        backend.values = [.enhanceDialogue: false]
        backend.onSet = { [weak backend] _, _ in backend?.values = [:] }
        let audio = SystemPlaybackAudio(backend: backend)
        await audio.setEnabled(true, for: .enhanceDialogue)
        XCTAssertEqual(audio.failure, .unavailable)
        XCTAssertTrue(audio.values.isEmpty)
        XCTAssertTrue(audio.pending.isEmpty)
    }

    func testCancelledRequestDoesNotWriteAndUnchangedRequestDoesNotPost() async {
        let backend = SystemAudioTestBackend()
        backend.values = [.reduceLoudSounds: false]
        let audio = SystemPlaybackAudio(backend: backend)
        await audio.setEnabled(false, for: .reduceLoudSounds)
        let task = Task { await audio.setEnabled(true, for: .reduceLoudSounds) }
        task.cancel()
        await task.value
        XCTAssertTrue(backend.writes.isEmpty)
        XCTAssertNil(audio.failure)
        XCTAssertTrue(audio.pending.isEmpty)
    }
}
#endif
