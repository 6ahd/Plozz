#if os(iOS)
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureFeedbackPresentationTests: XCTestCase {
    private var capturedImages: [(image: UIImage, name: String)] = []

    func testFirstForwardInsertionConfirmsOnceAndAdditionalTapRetriggers() async throws {
        try await assertBriefConfirmation(direction: .forward)
    }

    func testFirstBackwardInsertionConfirmsOnceAndAdditionalTapRetriggers() async throws {
        try await assertBriefConfirmation(direction: .backward)
    }

    func testForwardChevronsFlowIntoLeadingSlotWithoutReversing() async throws {
        try await assertDirectionalFlow(direction: .forward)
    }

    func testBackwardChevronsFlowIntoLeadingSlotWithoutReversing() async throws {
        try await assertDirectionalFlow(direction: .backward)
    }

    func testRapidForwardTapsPreserveFlowAndCoalesceToOneAdditionalCycle() async throws {
        try await assertRapidTapFlow(direction: .forward)
    }

    func testRapidBackwardTapsPreserveFlowAndCoalesceToOneAdditionalCycle() async throws {
        try await assertRapidTapFlow(direction: .backward)
    }

    func testReduceMotionRendersExactlyTwoSteadyChevronsAcrossAdditionalTaps() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(reduceMotion: true) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(120))
                let first = try self.capture(window, direction: direction)
                XCTAssertEqual(self.componentCount(first.reference), 2, "Render exactly two directional chevrons")
                try await Task.sleep(for: .milliseconds(160))
                let later = try self.capture(window, direction: direction)
                XCTAssertTrue(first.reference == later.reference, "The reference HUD must remain pixel-identical")
                XCTAssertTrue(first.subject == later.subject, "The subject HUD must remain pixel-identical")

                _ = fixture.subject.seek(by: interval, from: 300, within: 0...600)
                try await Task.sleep(for: .milliseconds(180))
                let repeated = try self.capture(window, direction: direction)
                // Different vertical origins can rasterize differently; compare the same HUD before and after the tap.
                XCTAssertTrue(
                    later.subject == repeated.subject, "Updating the total must leave its glyph pixels unchanged"
                )
                XCTAssertEqual(fixture.subject.skip?.seconds, interval * 2)
                XCTAssertEqual(fixture.subject.skip?.direction, direction)
                try await Task.sleep(for: .milliseconds(160))
                let continued = try self.capture(window, direction: direction)
                XCTAssertTrue(
                    repeated.subject == continued.subject, "Additional taps must not start animation under Reduce Motion"
                )
            }
        }
    }

    func testEnablingReduceMotionStopsAnAlreadyVisibleConfirmation() async throws {
        try await withFeedback { fixture, window in
            fixture.seek(by: 25)
            try await Task.sleep(for: .milliseconds(70))
            fixture.reduceMotion = true
            try await Task.sleep(for: .milliseconds(40))
            let stopped = try self.capture(window, direction: .forward)
            XCTAssertEqual(self.componentCount(stopped.subject), 2)
            try await Task.sleep(for: .milliseconds(180))
            let later = try self.capture(window, direction: .forward)
            XCTAssertTrue(
                stopped.subject == later.subject, "Enabling Reduce Motion must leave the HUD pixel-identical over time"
            )
        }
    }

    private func assertBriefConfirmation(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let interval: TimeInterval = direction == .forward ? 25 : -25
            XCTAssertNil(fixture.subject.skip)
            var previousRest: [UInt8]?
            for pulse in 1...2 {
                let startedAt = ContinuousClock.now
                fixture.seek(by: interval)
                try await Task.sleep(until: startedAt + .milliseconds(60), clock: .continuous)
                let first = try self.capture(window, direction: direction)
                try await Task.sleep(until: startedAt + .milliseconds(180), clock: .continuous)
                let moving = try self.capture(window, direction: direction)
                XCTAssertGreaterThan(
                    self.difference(first.subject, moving.subject), 0.12,
                    "Skip pulse \(pulse) must visibly move during its brief confirmation"
                )
                if let previousRest {
                    XCTAssertGreaterThan(
                        self.difference(previousRest, first.subject), 0.12,
                        "An accepted additional tap must restart confirmation from the resting HUD"
                    )
                }

                // Use pulse-relative deadlines so screenshot work does not accumulate into the waits.
                try await Task.sleep(until: startedAt + .milliseconds(450), clock: .continuous)
                let settled = try self.capture(window, direction: direction)
                try await Task.sleep(until: startedAt + .milliseconds(650), clock: .continuous)
                let resting = try self.capture(window, direction: direction)
                XCTAssertTrue(
                    settled.subject == resting.subject,
                    "Skip pulse \(pulse) must finish by 450 ms and leave exactly static glyph pixels"
                )
                XCTAssertEqual(self.componentCount(resting.subject), 2, "Both chevrons must remain visible at rest")
                XCTAssertEqual(fixture.subject.skip?.seconds, interval * Double(pulse), "The cumulative HUD must remain visible")
                XCTAssertEqual(fixture.subject.skip?.pulse, pulse)
                XCTAssertEqual(fixture.subject.skip?.direction, direction)
                if let previousRest {
                    XCTAssertTrue(
                        previousRest == resting.subject,
                        "Each confirmation must return to the same HUD's resting glyph pixels"
                    )
                }
                previousRest = resting.subject
            }
        }
    }

    private func assertDirectionalFlow(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let startedAt = ContinuousClock.now
            fixture.seek(by: direction == .forward ? 25 : -25)
            let sign = direction == .forward ? 1.0 : -1.0
            var previousX: Double?
            for milliseconds in [60, 140, 220] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                let frame = try self.capture(window, direction: direction, afterScreenUpdates: false)
                let positions = self.glyphCentroids(frame.subject)
                if let priorX = previousX {
                    // Follow the original trailing glyph, not the fading/wrapped glyph behind it.
                    let advancing = positions.filter {
                        let displacement = ($0 - priorX) * sign
                        return displacement > 1 && displacement < 12
                    }
                    XCTAssertEqual(
                        advancing.count, 1,
                        "The trailing glyph must advance in the skip direction without wobbling: \(priorX) → \(positions)"
                    )
                    previousX = try XCTUnwrap(advancing.first)
                } else {
                    previousX = try XCTUnwrap(direction == .forward ? positions.min() : positions.max())
                }
            }
        }
    }

    private func assertRapidTapFlow(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Keep totals two digits so text layout cannot shift the glyph comparison.
            // The reference queues one cycle; the subject receives five rapid accepted taps.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [80, 100, 120, 140, 160] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    if milliseconds == 80 {
                        _ = fixture.reference.seek(by: sign * 5, from: 300, within: 0...600)
                    }
                    _ = fixture.subject.seek(by: sign * 5, from: 300, within: 0...600)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }

            try await Task.sleep(until: startedAt + .milliseconds(50), clock: .continuous)
            let initial = try self.capture(window, direction: direction, afterScreenUpdates: false)
            XCTAssertLessThan(self.difference(initial.reference, initial.subject), 0.12)
            try await Task.sleep(until: startedAt + .milliseconds(200), clock: .continuous)
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(280), "The entire burst must land in the first cycle")
            let duringBurst = try self.capture(window, direction: direction, afterScreenUpdates: false)
            XCTAssertGreaterThan(self.difference(initial.subject, duringBurst.subject), 0.12)
            XCTAssertLessThan(
                self.difference(duringBurst.reference, duringBurst.subject), 0.12,
                "Rapid taps must preserve the original rendered phase, not restart or cancel it"
            )

            try await Task.sleep(until: startedAt + .milliseconds(340), clock: .continuous)
            let queued = try self.capture(window, direction: direction, afterScreenUpdates: false)
            try await Task.sleep(until: startedAt + .milliseconds(450), clock: .continuous)
            let queuedLater = try self.capture(window, direction: direction, afterScreenUpdates: false)
            XCTAssertGreaterThan(
                self.difference(queued.subject, queuedLater.subject), 0.12,
                "Accepted taps must produce one additional moving cycle after the initial 280 ms"
            )
            for frame in [queued, queuedLater] {
                XCTAssertLessThan(
                    self.difference(frame.reference, frame.subject), 0.12,
                    "One queued tap and five coalesced taps must remain in the same rendered phase"
                )
            }

            try await Task.sleep(until: startedAt + .milliseconds(650), clock: .continuous)
            let settled = try self.capture(window, direction: direction)
            try await Task.sleep(until: startedAt + .milliseconds(850), clock: .continuous)
            let resting = try self.capture(window, direction: direction)
            XCTAssertTrue(
                settled.subject == resting.subject,
                "The burst must stop after two 280 ms cycles, without an idle loop or per-tap backlog"
            )
            XCTAssertTrue(settled.reference == resting.reference, "The one-extra-cycle reference must also be static")
            XCTAssertEqual(self.componentCount(resting.subject), 2)
            XCTAssertEqual(fixture.subject.skip?.pulse, 6)
            XCTAssertEqual(fixture.subject.skip?.seconds, sign * 50, "All accepted taps must contribute to the visible total")
            XCTAssertEqual(fixture.subject.skip?.direction, direction)
            XCTAssertEqual(fixture.reference.skip?.pulse, 2)
        }
    }

    private func withFeedback(
        reduceMotion: Bool = false,
        _ operation: (FeedbackFixture, UIWindow) async throws -> Void
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let fixture = FeedbackFixture(reduceMotion: reduceMotion)
        let host = UIHostingController(rootView: FeedbackFixtureView(fixture: fixture))
        host.safeAreaRegions = []
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            fixture.reference.cancel()
            fixture.subject.cancel()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            // Serialize evidence after the short animation samples, not between them.
            for capture in capturedImages {
                let attachment = XCTAttachment(image: capture.image)
                attachment.name = capture.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            capturedImages.removeAll()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        try await operation(fixture, window)
    }

    private func capture(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, afterScreenUpdates: Bool = true
    ) throws -> (reference: [UInt8], subject: [UInt8]) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates))
        }
        capturedImages.append((image, "Skip confirmation \(direction)"))
        let cgImage = try XCTUnwrap(image.cgImage)
        // Isolate the glyph side of each fixed 400×200 HUD, excluding the changing total.
        let x: CGFloat = direction == .forward ? 325 : 15
        func pixels(y: CGFloat) throws -> [UInt8] {
            let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(x: x, y: y, width: 60, height: 48)))
            var bytes = [UInt8](repeating: 0, count: 60 * 48)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: 60, height: 48, bitsPerComponent: 8, bytesPerRow: 60,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                ))
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 60, height: 48))
            }
            XCTAssertGreaterThan(bytes.filter { $0 > 80 }.count, 30, "The captured HUD must contain visible glyphs")
            return bytes
        }
        return (try pixels(y: 76), try pixels(y: 276))
    }

    private func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        let difference = zip(lhs, rhs).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        let energy = max(lhs.reduce(0) { $0 + Int($1) }, rhs.reduce(0) { $0 + Int($1) })
        return Double(difference) / Double(max(energy, 1))
    }

    private func componentCount(_ pixels: [UInt8]) -> Int {
        glyphCentroids(pixels).count
    }

    private func glyphCentroids(_ pixels: [UInt8]) -> [Double] {
        var remaining = Set(pixels.indices.filter { pixels[$0] > 128 })
        var positions: [Double] = []
        while let seed = remaining.first {
            remaining.remove(seed)
            var queue = [seed]
            var size = 0
            var weightedX = 0
            var weight = 0
            while let index = queue.popLast() {
                size += 1
                weightedX += (index % 60) * Int(pixels[index])
                weight += Int(pixels[index])
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = index % 60 + dx
                        let y = index / 60 + dy
                        guard (0..<60).contains(x), (0..<48).contains(y) else { continue }
                        let neighbor = y * 60 + x
                        if remaining.remove(neighbor) != nil { queue.append(neighbor) }
                    }
                }
            }
            if size > 10 { positions.append(Double(weightedX) / Double(weight)) }
        }
        return positions.sorted()
    }
}

@MainActor
@Observable
private final class FeedbackFixture {
    let reference = PlayerTouchGestureState()
    let subject = PlayerTouchGestureState()
    var reduceMotion: Bool

    init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }

    func seek(by interval: TimeInterval) {
        _ = reference.seek(by: interval, from: 300, within: 0...600)
        _ = subject.seek(by: interval, from: 300, within: 0...600)
    }
}

private struct FeedbackFixtureView: View {
    let fixture: FeedbackFixture

    var body: some View {
        VStack(spacing: 0) {
            PlayerTouchGestureFeedbackContent(state: fixture.reference, reduceMotion: fixture.reduceMotion)
                .frame(width: 400, height: 200)
            PlayerTouchGestureFeedbackContent(state: fixture.subject, reduceMotion: fixture.reduceMotion)
                .frame(width: 400, height: 200)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .environment(\.locale, Locale(identifier: "en_US"))
        .ignoresSafeArea()
    }
}
#endif
