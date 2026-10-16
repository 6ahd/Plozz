#if os(iOS)
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureFeedbackPresentationTests: XCTestCase {
    private var capturedImages: [(image: UIImage, name: String)] = []

    func testFirstForwardInsertionAnimatesCompactIndicatorAndRetriggers() async throws {
        try await assertConfirmation(direction: .forward)
    }

    func testFirstBackwardInsertionAnimatesCompactIndicatorAndRetriggers() async throws {
        try await assertConfirmation(direction: .backward)
    }

    func testRapidForwardTapsRetargetWithoutRestFlashesOrQueuedReplay() async throws {
        try await assertRapidTaps(direction: .forward)
    }

    func testRapidBackwardTapsRetargetWithoutRestFlashesOrQueuedReplay() async throws {
        try await assertRapidTaps(direction: .backward)
    }

    func testReduceMotionRendersExactlyTwoSteadyChevronsAcrossAdditionalTaps() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(reduceMotion: true) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(120))
                let first = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion insertion")
                XCTAssertEqual(self.componentCount(first), 2)
                try await Task.sleep(for: .milliseconds(160))
                let later = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion still held")
                XCTAssertTrue(first.pixels == later.pixels, "Reduce Motion must remain exactly static")

                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(180))
                let repeated = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion additional tap")
                XCTAssertTrue(later.pixels == repeated.pixels, "Updating the total must not move the glyphs")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * 2)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                try await Task.sleep(for: .milliseconds(160))
                let held = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion repeated hold")
                XCTAssertTrue(repeated.pixels == held.pixels, "Additional taps must not start an animation")
                try self.assertCompactIndicator(held, window: window, direction: direction)
            }
        }
    }

    func testEnablingReduceMotionStopsAnAlreadyVisibleConfirmation() async throws {
        try await withFeedback { fixture, window in
            fixture.seek(by: 25)
            try await Task.sleep(for: .milliseconds(70))
            fixture.reduceMotion = true
            try await Task.sleep(for: .milliseconds(40))
            let stopped = try self.captureGlyphs(window, direction: .forward, label: "Reduce Motion activated")
            XCTAssertEqual(self.componentCount(stopped), 2)
            try await Task.sleep(for: .milliseconds(180))
            let later = try self.captureGlyphs(window, direction: .forward, label: "Reduce Motion remains static")
            XCTAssertTrue(stopped.pixels == later.pixels, "Enabling Reduce Motion must stop the visible spring")
        }
    }

    private func assertConfirmation(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let interval: TimeInterval = direction == .forward ? 25 : -25
            XCTAssertNil(fixture.state.skip)
            var previousRest: RenderedFrame?
            for pulse in 1...2 {
                let startedAt = ContinuousClock.now
                fixture.seek(by: interval)
                var frames: [Int: RenderedFrame] = [:]
                for milliseconds in [60, 180, 700, 850] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    frames[milliseconds] = try self.captureGlyphs(
                        window, direction: direction, label: "Pulse \(pulse), target \(milliseconds) ms", since: startedAt
                    )
                }
                let early = try XCTUnwrap(frames[60])
                let later = try XCTUnwrap(frames[180])
                let settled = try XCTUnwrap(frames[700])
                let held = try XCTUnwrap(frames[850])
                XCTAssertGreaterThan(self.difference(early, later), 0.12, "Each accepted pulse must visibly animate")
                if let previousRest {
                    XCTAssertGreaterThan(self.difference(previousRest, early), 0.12, "A later tap must retrigger confirmation")
                    XCTAssertTrue(previousRest.pixels == held.pixels, "Native completion must restore the same resting glyphs")
                }
                XCTAssertTrue(settled.pixels == held.pixels, "One confirmation must settle, not become an idle loop")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * Double(pulse), "The cumulative HUD must still be present")
                XCTAssertEqual(fixture.state.skip?.pulse, pulse)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                try self.assertCompactIndicator(held, window: window, direction: direction)
                previousRest = held
            }
        }
    }

    private func assertRapidTaps(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Two-digit totals keep text layout out of the glyph continuity comparison.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [80, 105, 130, 155, 180] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    fixture.seek(by: sign * 5)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }
            var frames: [Int: RenderedFrame] = [:]
            for milliseconds in [60, 95, 130, 165, 220, 280, 360, 440, 520, 600, 700, 850, 1000] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                frames[milliseconds] = try self.captureGlyphs(
                    window, direction: direction, label: "Rapid taps, target \(milliseconds) ms", since: startedAt
                )
            }
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(300), "The burst must occur during the first spring")
            let held = try XCTUnwrap(frames[850])
            let settled = try XCTUnwrap(frames[1000])
            let finalDeltas = zip(settled.pixels, held.pixels).map { abs(Int($0.0) - Int($0.1)) }
            XCTAssertLessThanOrEqual(
                finalDeltas.max() ?? 0, 2,
                "The rapid-tap tail may retain only two 8-bit levels of edge rasterization noise"
            )
            XCTAssertGreaterThan(
                self.difference(try XCTUnwrap(frames[60]), try XCTUnwrap(frames[220])), 0.12,
                "The burst must retain visible motion, not cancel the confirmation"
            )
            for milliseconds in [95, 130, 165] {
                XCTAssertGreaterThan(
                    self.difference(try XCTUnwrap(frames[milliseconds]), held), 0.12,
                    "Retargeting at \(milliseconds) ms must not flash the resting glyphs mid-spring"
                )
            }
            // A damped spring may rebound, but a queued full handover would restore its initial
            // amplitude or visibly displace the resting glyph geometry.
            func meanDelta(_ frame: RenderedFrame) -> Double {
                let total = zip(frame.pixels, held.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                return Double(total) / Double(held.pixels.count)
            }
            var initialPeak: Double = 0
            for milliseconds in [60, 95, 130, 165, 220, 280] {
                initialPeak = max(initialPeak, meanDelta(try XCTUnwrap(frames[milliseconds])))
            }
            let restBounds = try self.inkBounds(held)
            for milliseconds in [360, 440, 520, 600, 700] {
                let frame = try XCTUnwrap(frames[milliseconds])
                XCTAssertLessThan(
                    meanDelta(frame), initialPeak * 0.5,
                    "The late rebound at \(milliseconds) ms must remain below half a full rendered handover"
                )
                let bounds = try self.inkBounds(frame)
                let edgeDisplacements: [CGFloat] = [
                    abs(bounds.minX - restBounds.minX), abs(bounds.maxX - restBounds.maxX),
                    abs(bounds.minY - restBounds.minY), abs(bounds.maxY - restBounds.maxY)
                ]
                XCTAssertLessThanOrEqual(
                    edgeDisplacements.max() ?? 0, 1,
                    "The late glyph geometry at \(milliseconds) ms must stay within one pixel of rest"
                )
            }
            XCTAssertEqual(fixture.state.skip?.pulse, 6)
            XCTAssertEqual(fixture.state.skip?.seconds, sign * 50, "Every accepted tap must contribute to the held total")
            XCTAssertEqual(fixture.state.skip?.direction, direction)
            try self.assertCompactIndicator(held, window: window, direction: direction)
        }
    }

    private func assertCompactIndicator(
        _ glyphs: RenderedFrame, window: UIWindow, direction: PlayerTouchSkipDirection
    ) throws {
        XCTAssertEqual(componentCount(glyphs), 2, "The resting indicator must retain exactly two open chevrons")
        let glyphBounds = try inkBounds(glyphs)
        XCTAssertGreaterThanOrEqual(glyphBounds.width, 20)
        XCTAssertGreaterThanOrEqual(glyphBounds.height, 18)
        XCTAssertLessThanOrEqual(glyphBounds.width, 26, "The 30-point glyph canvas must be smaller than the old 36-point artwork")
        XCTAssertLessThanOrEqual(glyphBounds.height, 24)
        let center: CGFloat = direction == .forward ? 312 : 88
        let indicator = try capture(
            window, rect: CGRect(x: center - 65, y: 72, width: 130, height: 56),
            label: "\(direction) — complete compact indicator"
        )
        let indicatorBounds = try inkBounds(indicator)
        XCTAssertLessThanOrEqual(indicatorBounds.width, 100, "The count and chevrons must retain the compact font and spacing")
        XCTAssertLessThanOrEqual(indicatorBounds.height, 28)
    }

    private func withFeedback(
        reduceMotion: Bool = false, _ operation: (FeedbackFixture, UIWindow) async throws -> Void
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
            fixture.state.cancel()
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
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

    private struct RenderedFrame {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private func captureGlyphs(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, label: String,
        since: ContinuousClock.Instant? = nil
    ) throws -> RenderedFrame {
        let x: CGFloat = direction == .forward ? 325 : 15
        let frame = try capture(
            window, rect: CGRect(x: x, y: 76, width: 60, height: 48), label: "\(direction) — \(label)", since: since
        )
        XCTAssertGreaterThan(frame.pixels.filter { $0 > 80 }.count, 30, "The presented glyphs must remain visible")
        return frame
    }

    private func capture(
        _ window: UIWindow, rect: CGRect, label: String, since: ContinuousClock.Instant? = nil
    ) throws -> RenderedFrame {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let capturedAt = ContinuousClock.now
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: false))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let duration = milliseconds(from: capturedAt, to: ContinuousClock.now)
        let elapsed = since.map { "actual \(milliseconds(from: $0, to: capturedAt)) ms, " } ?? ""
        capturedImages.append((image, "\(label) — \(elapsed)capture \(duration) ms"))
        return RenderedFrame(width: width, height: height, pixels: pixels)
    }

    private func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: end).components
        return Int(duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000)
    }

    private func difference(_ lhs: RenderedFrame, _ rhs: RenderedFrame) -> Double {
        let difference = zip(lhs.pixels, rhs.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        let energy = max(lhs.pixels.reduce(0) { $0 + Int($1) }, rhs.pixels.reduce(0) { $0 + Int($1) })
        return Double(difference) / Double(max(energy, 1))
    }

    private func inkBounds(_ frame: RenderedFrame) throws -> CGRect {
        let ink = frame.pixels.indices.filter { frame.pixels[$0] > 128 }
        let xs = ink.map { $0 % frame.width }
        let ys = ink.map { $0 / frame.width }
        let minX = try XCTUnwrap(xs.min())
        let minY = try XCTUnwrap(ys.min())
        let maxX = try XCTUnwrap(xs.max())
        let maxY = try XCTUnwrap(ys.max())
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func componentCount(_ frame: RenderedFrame) -> Int {
        var remaining = Set(frame.pixels.indices.filter { frame.pixels[$0] > 128 })
        var count = 0
        while let seed = remaining.first {
            remaining.remove(seed)
            var queue = [seed]
            var size = 0
            while let index = queue.popLast() {
                size += 1
                for dy in -1...1 {
                    for dx in -1...1 {
                        let x = index % frame.width + dx
                        let y = index / frame.width + dy
                        guard (0..<frame.width).contains(x), (0..<frame.height).contains(y) else { continue }
                        let neighbor = y * frame.width + x
                        if remaining.remove(neighbor) != nil { queue.append(neighbor) }
                    }
                }
            }
            if size > 10 { count += 1 }
        }
        return count
    }
}

@MainActor
@Observable
private final class FeedbackFixture {
    let state = PlayerTouchGestureState()
    var reduceMotion: Bool

    init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }

    func seek(by interval: TimeInterval) {
        _ = state.seek(by: interval, from: 300, within: 0...600)
    }
}

private struct FeedbackFixtureView: View {
    let fixture: FeedbackFixture

    var body: some View {
        PlayerTouchGestureFeedbackContent(state: fixture.state, reduceMotion: fixture.reduceMotion)
            .frame(width: 400, height: 200)
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.black)
            .environment(\.locale, Locale(identifier: "en_US"))
            .ignoresSafeArea()
    }
}
#endif
