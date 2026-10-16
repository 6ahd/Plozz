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

/// Keeps rapid taps relative to the requested position, not a lagging playback clock.
@MainActor
@Observable
public final class PlayerTouchGestureState {
    public private(set) var skip: PlayerTouchSkipFeedback?
    public private(set) var boostRate: Double?
    public var isPinching = false
    private var feedbackTask: Task<Void, Never>?
    private var pulse = 0

    public init() {}

    public var isActive: Bool { skip != nil || boostRate != nil || isPinching }

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
        boostRate = rate
    }

    public func clearSkip() {
        feedbackTask?.cancel()
        feedbackTask = nil
        skip = nil
    }

    public func cancel() {
        clearSkip()
        boostRate = nil
        isPinching = false
    }
}
