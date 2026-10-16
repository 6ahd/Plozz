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
                HStack(spacing: 12) {
                    if skip.direction == .backward {
                        PlayerTouchSkipChevrons(direction: .backward, pulse: skip.pulse, reduceMotion: reduceMotion)
                    }
                    Text(skip.seconds, format: .number.sign(strategy: .always()).precision(.fractionLength(0)))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: skip.seconds)
                        .accessibilityIdentifier("player-gesture-skip-total")
                    if skip.direction == .forward {
                        PlayerTouchSkipChevrons(direction: .forward, pulse: skip.pulse, reduceMotion: reduceMotion)
                    }
                }
                .font(.system(size: 26, weight: .semibold))
                .modifier(PlayerTouchFeedbackPill())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("player-gesture-skip-pill")
                .position(x: geometry.size.width * (skip.direction == .backward ? 0.22 : 0.78),
                          y: geometry.size.height / 2)
                .environment(\.layoutDirection, .leftToRight)
            }
            if let rate = state.boostRate {
                HStack(spacing: 8) {
                    Text(verbatim: rate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                        .accessibilityIdentifier("player-gesture-speed")
                    Image(systemName: "forward.fill")
                        .accessibilityHidden(true)
                }
                .font(.title2.weight(.semibold).monospacedDigit())
                .modifier(PlayerTouchFeedbackPill())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("player-gesture-speed-pill")
                .padding(.top, 16)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }
}

private struct PlayerTouchFeedbackPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .modifier(PanelGlassBackground(cornerRadius: 999))
            .environment(\.colorScheme, .dark)
    }
}

private struct PlayerTouchSkipChevrons: View {
    let direction: PlayerTouchSkipDirection
    let pulse: Int
    let reduceMotion: Bool
    @State private var activePulses: [Int] = []

    var body: some View {
        Color.clear
            .frame(width: 30, height: 30)
            .overlay {
                ZStack {
                    if reduceMotion {
                        Image(systemName: "chevron.right")
                    } else {
                        ForEach(activePulses, id: \.self) { id in
                            PlayerTouchSkipChevronFlight {
                                activePulses.removeAll { $0 == id }
                            }
                            .transition(.identity)
                        }
                    }
                }
                .font(.system(size: 22, weight: .semibold))
                .scaleEffect(x: direction == .forward ? 1 : -1, y: 1)
            }
            .onChange(of: pulse, initial: true) {
                guard !reduceMotion else { return }
                activePulses.append(pulse)
            }
            .onChange(of: reduceMotion) { activePulses.removeAll() }
            .onDisappear { activePulses.removeAll() }
            .accessibilityHidden(true)
    }
}

private struct PlayerTouchSkipChevronFlight: View {
    private static let travelDuration = 0.25
    private static let holdDuration = 0.5
    private static let fadeDuration = 0.3

    let onCompletion: () -> Void
    @State private var isTraveling = false

    var body: some View {
        Image(systemName: "chevron.right")
            .offset(x: isTraveling ? 20 : 0)
            .animation(.easeOut(duration: Self.travelDuration), value: isTraveling)
            .opacity(isTraveling ? 0 : 1)
            .onAppear {
                withAnimation(
                    .easeIn(duration: Self.fadeDuration).delay(Self.travelDuration + Self.holdDuration),
                    completionCriteria: .removed
                ) {
                    isTraveling = true
                } completion: {
                    onCompletion()
                }
            }
    }
}
#endif
