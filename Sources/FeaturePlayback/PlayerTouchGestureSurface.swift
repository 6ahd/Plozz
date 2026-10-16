#if os(iOS)
import SwiftUI
import UIKit

/// Lives behind the native controls, so their touches never become playback shortcuts.
public struct PlayerTouchGestureSurface: UIViewRepresentable {
    let state: PlayerTouchGestureState
    let shortcutsEnabled: Bool
    let canSeek: Bool
    let canBoost: Bool
    let canZoom: Bool
    let onTap: () -> Void
    let onSkip: (PlayerTouchSkipDirection) -> Void
    let onBoostChanged: (Bool) -> Void
    let onZoom: (Bool) -> Void
    let onGestureStarted: () -> Void

    public init(
        state: PlayerTouchGestureState, shortcutsEnabled: Bool,
        canSeek: Bool, canBoost: Bool, canZoom: Bool,
        onTap: @escaping () -> Void,
        onSkip: @escaping (PlayerTouchSkipDirection) -> Void,
        onBoostChanged: @escaping (Bool) -> Void,
        onZoom: @escaping (Bool) -> Void,
        onGestureStarted: @escaping () -> Void
    ) {
        self.state = state
        self.shortcutsEnabled = shortcutsEnabled
        self.canSeek = canSeek
        self.canBoost = canBoost
        self.canZoom = canZoom
        self.onTap = onTap
        self.onSkip = onSkip
        self.onBoostChanged = onBoostChanged
        self.onZoom = onZoom
        self.onGestureStarted = onGestureStarted
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        context.coordinator.install(in: view)
        return view
    }

    public func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(self)
    }

    public static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var owner: PlayerTouchGestureSurface
        private var pendingTap: Task<Void, Never>?
        private var pendingDirection: PlayerTouchSkipDirection?
        private var lastTapAt: TimeInterval = 0
        private var holding = false
        private var pinchApplied = false
        private let hold = UILongPressGestureRecognizer()
        private let pinch = UIPinchGestureRecognizer()

        init(_ owner: PlayerTouchGestureSurface) { self.owner = owner }

        func install(in view: UIView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            hold.addTarget(self, action: #selector(held(_:)))
            hold.minimumPressDuration = 1
            hold.allowableMovement = 12
            pinch.addTarget(self, action: #selector(pinched(_:)))
            for gesture in [tap, hold, pinch] {
                gesture.delegate = self
                view.addGestureRecognizer(gesture)
            }
            tap.require(toFail: hold)
            update(owner)
        }

        func update(_ owner: PlayerTouchGestureSurface) {
            self.owner = owner
            let enabled = owner.shortcutsEnabled && !UIAccessibility.isVoiceOverRunning
            hold.isEnabled = enabled && owner.canBoost
            pinch.isEnabled = enabled && owner.canZoom
            if !enabled { cancel() }
        }

        func cancel() {
            cancelPendingTap()
            finishHold()
            owner.state.isPinching = false
        }

        private func cancelPendingTap() {
            pendingTap?.cancel()
            pendingTap = nil
            pendingDirection = nil
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let x = gesture.location(in: view).x
            let direction: PlayerTouchSkipDirection? = x < view.bounds.width * 0.35
                ? .backward : (x > view.bounds.width * 0.65 ? .forward : nil)
            guard owner.shortcutsEnabled, owner.canSeek,
                  !UIAccessibility.isVoiceOverRunning, let direction else {
                cancelPendingTap()
                owner.state.clearSkip()
                owner.onTap()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if owner.state.skip != nil
                || (pendingTap != nil && pendingDirection == direction && now - lastTapAt <= 0.32) {
                cancelPendingTap()
                owner.onSkip(direction)
                return
            }
            if pendingTap != nil {
                cancelPendingTap()
                owner.onTap()
            }
            pendingDirection = direction
            lastTapAt = now
            pendingTap = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(320)) }
                catch { return }
                guard let self else { return }
                self.pendingTap = nil
                self.pendingDirection = nil
                self.owner.onTap()
            }
        }

        @objc private func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                cancelPendingTap()
                holding = true
                owner.onBoostChanged(true)
            case .ended, .cancelled, .failed:
                finishHold()
            default:
                break
            }
        }

        private func finishHold() {
            guard holding else { return }
            holding = false
            owner.onBoostChanged(false)
        }

        @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                cancelPendingTap()
                finishHold()
                owner.state.clearSkip()
                owner.state.isPinching = true
                pinchApplied = false
                owner.onGestureStarted()
            case .changed:
                guard !pinchApplied else { return }
                if gesture.scale > 1.12 || gesture.scale < 0.88 {
                    pinchApplied = true
                    owner.onZoom(gesture.scale > 1)
                }
            case .ended, .cancelled, .failed:
                owner.state.isPinching = false
            default:
                break
            }
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            let point = touch.location(in: view)
            // Leave edge-origin system navigation and the home indicator alone.
            let edges = view.safeAreaInsets
            return point.x > max(16, edges.left) && point.x < view.bounds.width - max(16, edges.right)
                && point.y > max(12, edges.top) && point.y < view.bounds.height - max(12, edges.bottom)
        }
    }
}

public struct PlayerTouchGestureFeedbackView: View {
    let state: PlayerTouchGestureState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: PlayerTouchGestureState) { self.state = state }

    public var body: some View {
        PlayerTouchGestureFeedbackContent(state: state, reduceMotion: reduceMotion)
    }
}

struct PlayerTouchGestureFeedbackContent: View {
    let state: PlayerTouchGestureState
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            if let skip = state.skip {
                HStack(spacing: 16) {
                    if skip.direction == .backward {
                        PlayerTouchSkipChevrons(direction: .backward, pulse: skip.pulse, reduceMotion: reduceMotion)
                    }
                    Text(skip.seconds, format: .number.sign(strategy: .always()).precision(.fractionLength(0)))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("player-gesture-skip-total")
                    if skip.direction == .forward {
                        PlayerTouchSkipChevrons(direction: .forward, pulse: skip.pulse, reduceMotion: reduceMotion)
                    }
                }
                .font(.system(size: 30, weight: .semibold))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: skip.seconds)
                .position(x: geometry.size.width * (skip.direction == .backward ? 0.22 : 0.78),
                          y: geometry.size.height / 2)
                .environment(\.layoutDirection, .leftToRight)
            }
            if let rate = state.boostRate {
                Text(verbatim: rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .accessibilityIdentifier("player-gesture-speed")
                    .position(x: geometry.size.width / 2, y: 40)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
        .allowsHitTesting(false)
    }
}

private struct PlayerTouchSkipChevrons: View {
    let direction: PlayerTouchSkipDirection
    let pulse: Int
    let reduceMotion: Bool
    @State private var phase: Double = 0
    @State private var cycleBase: Double = 0
    @State private var isAnimating = false
    @State private var hasQueuedSkip = false
    @State private var generation = 0

    var body: some View {
        PlayerTouchSkipHandover(phase: phase, cycleBase: cycleBase, reduceMotion: reduceMotion)
            .scaleEffect(x: direction == .forward ? 1 : -1, y: 1)
            .onChange(of: pulse, initial: true) {
                guard !reduceMotion else { return }
                if isAnimating {
                    hasQueuedSkip = true
                } else {
                    animateSkip()
                }
            }
            .onChange(of: reduceMotion) {
                if reduceMotion { cancelAnimation() }
            }
            .onDisappear { cancelAnimation() }
            .accessibilityHidden(true)
    }

    private func animateSkip() {
        isAnimating = true
        hasQueuedSkip = false
        generation &+= 1
        let token = generation
        cycleBase = phase
        withAnimation(.spring(response: 0.425, dampingFraction: 0.8),
                      completionCriteria: .logicallyComplete) {
            phase = cycleBase + 1
        } completion: {
            guard generation == token else { return }
            if hasQueuedSkip {
                animateSkip()
            } else {
                isAnimating = false
            }
        }
    }

    private func cancelAnimation() {
        generation &+= 1
        isAnimating = false
        hasQueuedSkip = false
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            phase = 0
            cycleBase = 0
        }
    }
}

// Adapted from Mozz's TransportGlyph (GPL-3.0), copyright 2026 Mozz contributors.
private struct PlayerTouchSkipHandover: View, Animatable {
    var phase: Double
    let cycleBase: Double
    let reduceMotion: Bool
    private let size: CGFloat = 36

    // Evaluate the staged handover at each interpolated spring frame.
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    private var handover: Double { reduceMotion ? 0 : min(1, max(0, phase - cycleBase)) }
    private var unit: CGFloat { size / 24 }
    private var exitProgress: Double { ramp(handover, from: 0, to: 0.55) }

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    chevron(back: 4)
                        .scaleEffect(1 - ramp(exitProgress, from: 0.15, to: 0.9),
                                     anchor: UnitPoint(x: 12 / 24, y: 0.5))
                        .offset(x: 17 * unit * exitProgress)
                        .opacity(1 - ramp(exitProgress, from: 0.55, to: 0.88))
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: 21 * unit)
                        }
                    chevron(back: 4)
                        .scaleEffect(ramp(handover, from: 0.3, to: 0.94))
                        .offset(x: -17 * unit * (1 - ramp(handover, from: 0.3, to: 1)))
                    chevron(back: 13)
                        .scaleEffect(x: 1 - 0.18 * impact, y: 1 + 0.14 * impact,
                                     anchor: UnitPoint(x: 17 / 24, y: 0.5))
                        .offset(x: 1.1 * unit * impact)
                }
            }
    }

    private func chevron(back: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: back * unit, y: 4.5 * unit))
            path.addLine(to: CGPoint(x: (back + 8) * unit, y: 12 * unit))
            path.addLine(to: CGPoint(x: back * unit, y: 19.5 * unit))
        }
        .stroke(style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }

    private var impact: Double {
        let window = ramp(handover, from: 0.05, to: 0.55)
        guard window > 0, window < 1 else { return 0 }
        return pow(sin(.pi * window), 1.5)
    }

    private func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
        min(1, max(0, (value - start) / (end - start)))
    }
}
#endif
