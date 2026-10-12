#if os(iOS)
import XCTest
@testable import CoreUI
import CoreModels
import FeatureLiveTVCore
@testable import FeatureLiveTV

@MainActor
final class TouchFeedbackTests: XCTestCase {
    func testImmediateActionsAreSilentWhileInactive() {
        var events: [TouchFeedback.Event] = []
        var active = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { active }, now: { 0 })
        feedback.emit(.impact)
        feedback.emit(.selection)
        active = false
        feedback.emit(.impact)
        feedback.emit(.selection)
        XCTAssertEqual(events, [.impact, .selection])
    }

    func testConfirmationIsExplicitAndOneShot() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true }, now: { 0 })
        let confirm = feedback.confirmation()
        XCTAssertTrue(events.isEmpty)
        confirm()
        confirm()
        XCTAssertEqual(events, [.confirmation])
    }

    func testDelayedAndStaleProfileConfirmationsStaySilent() {
        var events: [TouchFeedback.Event] = []
        var time: TimeInterval = 0
        var sameProfile = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true }, now: { time })
        let delayed = feedback.confirmation()
        time = 3.001
        delayed()
        let changedProfile = feedback.confirmation(isRelevant: { sameProfile })
        sameProfile = false
        changedProfile()
        sameProfile = true
        changedProfile()
        XCTAssertTrue(events.isEmpty)
        feedback.confirmation()()
        XCTAssertEqual(events, [.confirmation])
    }

    func testBackgroundCompletionIsConsumedWithoutReplayingOnReturn() {
        var events: [TouchFeedback.Event] = []
        var active = true
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { active }, now: { 0 })
        let confirm = feedback.confirmation()
        active = false
        confirm()
        active = true
        confirm()
        XCTAssertTrue(events.isEmpty)
    }

    func testChannelFavoriteConfirmsOnlySuccessfulUserWrites() {
        var events: [TouchFeedback.Event] = []
        let feedback = TouchFeedback(output: { events.append($0) }, isActive: { true }, now: { 0 })
        let store = FavoriteStore()
        let model = LiveTVPrototypeModel(preferencesStore: store)
        model.toggleFavoriteWithFeedback("channel", feedback: feedback)
        XCTAssertTrue(model.favoriteIDs.contains("channel"))
        XCTAssertEqual(events, [.confirmation])

        store.fails = true
        model.toggleFavoriteWithFeedback("channel", feedback: feedback)
        XCTAssertTrue(model.favoriteIDs.contains("channel"))
        XCTAssertEqual(events, [.confirmation])

        store.fails = false
        model.retryPreferences()
        XCTAssertFalse(model.favoriteIDs.contains("channel"))
        XCTAssertEqual(events, [.confirmation], "Background/retry persistence is not a user gesture")
        model.toggleFavoriteWithFeedback("channel", feedback: feedback)
        model.toggleFavoriteWithFeedback("channel", feedback: feedback)
        XCTAssertEqual(events, [.confirmation, .confirmation, .confirmation])
    }
}

private final class FavoriteStore: LiveTVPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var failure = false
    private var value = LiveTVPreferences()
    var fails: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failure }
        set { lock.lock(); defer { lock.unlock() }; failure = newValue }
    }
    func load() throws -> LiveTVPreferences {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func save(_ value: LiveTVPreferences) throws {
        lock.lock()
        defer { lock.unlock() }
        if failure { throw CocoaError(.fileWriteUnknown) }
        self.value = value
    }
}
#endif
