import Foundation
import Observation

public enum PlayerTouchSkipDirection: Equatable, Sendable {
    case backward, forward
}

public struct PlayerTouchSkipFeedback: Equatable, Sendable {
    public let seconds: TimeInterval
    public let target: TimeInterval
    public let pulse: Int

    public var direction: PlayerTouchSkipDirection { seconds < 0 ? .backward : .forward }
}

public enum PlayerTouchLevel: Equatable, Sendable {
    case brightness, volume
}

public struct PlayerTouchLevelFeedback: Equatable, Sendable {
    public let kind: PlayerTouchLevel
    /// Nil means this output cannot currently be adjusted.
    public let value: Double?
}

struct PlayerTouchLevelDrag {
    let kind: PlayerTouchLevel
    let startValue: Double
    let height: Double

    static func kind(at x: Double, width: Double) -> PlayerTouchLevel? {
        guard x.isFinite, width.isFinite, width > 0, x >= 0, x <= width else { return nil }
        if x < width * 0.3 { return .brightness }
        if x > width * 0.7 { return .volume }
        return nil
    }

    func value(translationY: Double) -> Double? {
        guard translationY.isFinite, startValue.isFinite, height.isFinite, height > 0 else { return nil }
        return min(max(startValue - translationY / height, 0), 1)
    }
}

/// Keeps rapid taps relative to the requested position, not a lagging playback clock.
@MainActor
@Observable
public final class PlayerTouchGestureState {
    public private(set) var skip: PlayerTouchSkipFeedback?
    public private(set) var boostRate: Double?
    public var isPinching = false
    public private(set) var level: PlayerTouchLevelFeedback?
    private var feedbackTask: Task<Void, Never>?
    private var levelFeedbackTask: Task<Void, Never>?
    private var pulse = 0

    public init() {}

    public var isActive: Bool { skip != nil || boostRate != nil || isPinching || level != nil }

    public func showLevel(_ kind: PlayerTouchLevel, value: Double?) {
        clearSkip()
        clearLevel()
        level = PlayerTouchLevelFeedback(kind: kind, value: value)
    }

    public func finishLevel() {
        guard level != nil, levelFeedbackTask == nil else { return }
        levelFeedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            self?.level = nil
            self?.levelFeedbackTask = nil
        }
    }

    public func clearLevel() {
        levelFeedbackTask?.cancel()
        levelFeedbackTask = nil
        level = nil
    }

    public func seek(
        by interval: TimeInterval,
        from position: TimeInterval,
        within range: ClosedRange<TimeInterval>
    ) -> TimeInterval? {
        guard interval.isFinite, interval != 0, position.isFinite,
              range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        let start = min(max(skip?.target ?? position, range.lowerBound), range.upperBound)
        let target = min(max(start + interval, range.lowerBound), range.upperBound)
        let delta = target - start
        guard delta != 0 else { return nil }
        clearLevel()
        let previous = skip?.seconds ?? 0
        let accumulated = previous.sign == delta.sign ? previous + delta : delta
        pulse &+= 1
        skip = PlayerTouchSkipFeedback(seconds: accumulated, target: target, pulse: pulse)
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) }
            catch { return }
            self?.skip = nil
            self?.feedbackTask = nil
        }
        return target
    }

    public func showBoost(rate: Double?) {
        clearSkip()
        if rate != nil { clearLevel() }
        boostRate = rate
    }

    public func clearSkip() {
        feedbackTask?.cancel()
        feedbackTask = nil
        skip = nil
    }

    public func cancel() {
        clearSkip()
        clearLevel()
        boostRate = nil
        isPinching = false
    }
}
