#if canImport(SwiftUI)
import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
public final class TouchFeedback {
    public enum Event: Equatable {
        case impact
        case selection
        case confirmation
    }

    public static let shared = TouchFeedback()
    private let output: (Event) -> Void
    private let isActive: () -> Bool
    private let now: () -> TimeInterval

    init(
        output: @escaping (Event) -> Void,
        isActive: @escaping () -> Bool,
        now: @escaping () -> TimeInterval
    ) {
        self.output = output
        self.isActive = isActive
        self.now = now
    }

    private convenience init() {
        self.init(output: { event in
            #if os(iOS)
            switch event {
            case .impact: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            case .selection: UISelectionFeedbackGenerator().selectionChanged()
            case .confirmation: UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            #endif
        }, isActive: {
            #if os(iOS)
            UIApplication.shared.applicationState == .active
            #else
            false
            #endif
        }, now: { ProcessInfo.processInfo.systemUptime })
    }

    public func emit(_ event: Event) {
        guard isActive() else { return }
        output(event)
    }

    /// Capture at the gesture, invoke only after success. Delayed retries stay silent.
    public func confirmation(isRelevant: @escaping () -> Bool = { true }) -> @MainActor @Sendable () -> Void {
        let deadline = now() + 3
        var consumed = false
        return { [weak self] in
            guard !consumed else { return }
            consumed = true
            guard let self, self.now() <= deadline, isRelevant() else { return }
            self.emit(.confirmation)
        }
    }
}
#endif
