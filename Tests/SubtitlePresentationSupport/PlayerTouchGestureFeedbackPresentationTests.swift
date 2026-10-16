#if os(iOS)
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureFeedbackPresentationTests: XCTestCase {
    private var capturedImages: [(image: UIImage, name: String)] = []

    func testFirstForwardChevronTravelsFadesAndRetriggersWhileCountRemains() async throws {
        try await assertFlight(direction: .forward)
    }

    func testFirstBackwardChevronTravelsFadesAndRetriggersWhileCountRemains() async throws {
        try await assertFlight(direction: .backward)
    }

    func testRapidForwardTapsStackIndependentFlightsWithoutQueuedReplay() async throws {
        try await assertRapidTaps(direction: .forward)
    }

    func testRapidBackwardTapsStackIndependentFlightsWithoutQueuedReplay() async throws {
        try await assertRapidTaps(direction: .backward)
    }

    func testReduceMotionRendersOneSteadyCompactChevronAcrossAdditionalTaps() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(reduceMotion: true) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(120))
                let first = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion insertion")
                XCTAssertEqual(self.componentCount(first), 1)
                try await Task.sleep(for: .milliseconds(160))
                let later = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion still held")
                XCTAssertTrue(first.pixels == later.pixels, "Reduce Motion must remain exactly static")

                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(180))
                let repeated = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion additional tap")
                XCTAssertTrue(later.pixels == repeated.pixels, "Updating the total must not move the glyphs")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * 2)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                XCTAssertEqual(fixture.state.skip?.target, 300 + interval * 2)
                try await Task.sleep(for: .milliseconds(160))
                let held = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion repeated hold")
                XCTAssertTrue(repeated.pixels == held.pixels, "Additional taps must not start an animation")
                try self.assertCompactIndicator(held, window: window, direction: direction)
            }
        }
    }

    func testEnablingReduceMotionReplacesOverlappingFlightsWithOneSteadyChevron() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(140))
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(60))
                let moving = try self.captureGlyphs(window, direction: direction, label: "Before Reduce Motion")
                self.assertVisible(moving)
                fixture.reduceMotion = true
                try await Task.sleep(for: .milliseconds(80))
                let stopped = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion activated")
                XCTAssertEqual(self.componentCount(stopped), 1)
                try self.assertCompactIndicator(stopped, window: window, direction: direction)
                try await Task.sleep(for: .milliseconds(350))
                let later = try self.captureGlyphs(window, direction: direction, label: "Past both flight completions")
                XCTAssertTrue(stopped.pixels == later.pixels, "Disposed flights must not disturb the steady chevron")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * 2)
            }
        }
    }

    private func assertFlight(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let interval: TimeInterval = direction == .forward ? 25 : -25
            XCTAssertNil(fixture.state.skip)
            var lastPulseAt = ContinuousClock.now
            for pulse in 1...2 {
                let startedAt = ContinuousClock.now
                lastPulseAt = startedAt
                fixture.seek(by: interval)
                var frames: [Int: RenderedFrame] = [:]
                for milliseconds in [60, 200, 520, 850] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    frames[milliseconds] = try self.captureGlyphs(
                        window, direction: direction, label: "Pulse \(pulse), target \(milliseconds) ms", since: startedAt
                    )
                }
                let early = try XCTUnwrap(frames[60])
                let later = try XCTUnwrap(frames[200])
                self.assertVisible(early)
                self.assertVisible(later)
                XCTAssertEqual(self.componentCount(early), 1, "Each isolated tap must launch one open chevron")
                XCTAssertGreaterThan(self.difference(early, later), 0.12, "Each accepted pulse must visibly animate")
                let travel = self.horizontalCentroid(later) - self.horizontalCentroid(early)
                XCTAssertGreaterThan(
                    travel * (direction == .forward ? 1 : -1), 3,
                    "The chevron must translate outward, not just fade or scale in place"
                )
                XCTAssertLessThan(
                    self.inkEnergy(later), self.inkEnergy(early) * 0.85,
                    "The traveling chevron must fade before it disappears"
                )
                self.assertAbsent(try XCTUnwrap(frames[520]))
                self.assertAbsent(try XCTUnwrap(frames[850]))
                XCTAssertEqual(fixture.state.skip?.seconds, interval * Double(pulse), "The cumulative HUD must still be present")
                XCTAssertEqual(fixture.state.skip?.pulse, pulse)
                XCTAssertEqual(fixture.state.skip?.direction, direction)
                XCTAssertEqual(fixture.state.skip?.target, 300 + interval * Double(pulse))
                try self.assertVisibleCompactCount(window, direction: direction)
            }
            try await Task.sleep(until: lastPulseAt + .milliseconds(1300), clock: .continuous)
            XCTAssertNil(fixture.state.skip, "Flight completion must not change the existing feedback expiry")
            let expired = try self.captureIndicator(window, direction: direction, label: "Feedback expired")
            self.assertAbsent(expired)
        }
    }

    private func assertRapidTaps(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Two-digit totals keep text layout out of the flight geometry comparison.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [140, 170, 200] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    fixture.seek(by: sign * 5)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }
            var frames: [Int: RenderedFrame] = [:]
            for milliseconds in [60, 230, 460] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                frames[milliseconds] = try self.captureGlyphs(
                    window, direction: direction, label: "Rapid taps, target \(milliseconds) ms", since: startedAt
                )
            }
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(300), "The burst must occur during the first flight")
            let single = try XCTUnwrap(frames[60])
            let overlap = try XCTUnwrap(frames[230])
            self.assertVisible(single)
            self.assertVisible(overlap)
            let singleBounds = try self.inkBounds(single, threshold: 32)
            let overlapBounds = try self.inkBounds(overlap, threshold: 32)
            // Overlapping glyphs can merge into one connected component. Their combined extent,
            // including the older outward flight, distinguishes a stack from one restarted glyph.
            XCTAssertGreaterThan(
                overlapBounds.width, singleBounds.width + 4,
                "Rapid taps must leave older flights visible beside the newer flights"
            )
            let outwardTravel = direction == .forward
                ? overlapBounds.maxX - singleBounds.maxX
                : singleBounds.minX - overlapBounds.minX
            XCTAssertGreaterThan(outwardTravel, 4, "A new tap must not reset the older outward flight")
            self.assertVisible(
                try XCTUnwrap(frames[460]),
                message: "The first flight's completion must not remove newer flights"
            )
            for milliseconds in [520, 700, 850] {
                try await Task.sleep(until: lastPulseAt + .milliseconds(milliseconds), clock: .continuous)
                let tail = try self.captureGlyphs(
                    window, direction: direction, label: "Burst tail, target \(milliseconds) ms", since: lastPulseAt
                )
                self.assertAbsent(
                    tail,
                    message: "All flights must disappear without replay \(milliseconds) ms after the last tap"
                )
            }
            XCTAssertEqual(fixture.state.skip?.pulse, 4)
            XCTAssertEqual(fixture.state.skip?.seconds, sign * 40, "Every accepted tap must contribute to the held total")
            XCTAssertEqual(fixture.state.skip?.direction, direction)
            XCTAssertEqual(fixture.state.skip?.target, 300 + sign * 40)
            try self.assertVisibleCompactCount(window, direction: direction)
        }
    }

    private func assertCompactIndicator(
        _ glyphs: RenderedFrame, window: UIWindow, direction: PlayerTouchSkipDirection
    ) throws {
        XCTAssertEqual(componentCount(glyphs), 1, "Reduce Motion must retain exactly one open chevron")
        let glyphBounds = try inkBounds(glyphs)
        XCTAssertGreaterThanOrEqual(glyphBounds.width, 8)
        XCTAssertGreaterThanOrEqual(glyphBounds.height, 14)
        XCTAssertLessThanOrEqual(glyphBounds.width, 18, "The native single chevron must fit the compact 30-point slot")
        XCTAssertLessThanOrEqual(glyphBounds.height, 26)
        let indicator = try captureIndicator(window, direction: direction, label: "Complete compact indicator")
        let indicatorBounds = try inkBounds(indicator)
        XCTAssertLessThanOrEqual(indicatorBounds.width, 100, "The count and chevrons must retain the compact font and spacing")
        XCTAssertLessThanOrEqual(indicatorBounds.height, 28)
    }

    private func assertVisibleCompactCount(_ window: UIWindow, direction: PlayerTouchSkipDirection) throws {
        let count = try capture(
            window, rect: CGRect(x: direction == .forward ? 260 : 75, y: 80, width: 65, height: 40),
            label: "\(direction) — count remains after flights fade"
        )
        assertVisible(count, message: "The accumulated count must remain after the chevrons have disappeared")
        let bounds = try inkBounds(count)
        XCTAssertGreaterThanOrEqual(bounds.height, 18)
        XCTAssertLessThanOrEqual(bounds.height, 28, "The count must retain its compact 26-point font")
        XCTAssertLessThanOrEqual(bounds.width, 60)
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
        return try capture(
            window, rect: CGRect(x: x, y: 76, width: 60, height: 48), label: "\(direction) — \(label)", since: since
        )
    }

    private func captureIndicator(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, label: String
    ) throws -> RenderedFrame {
        let center: CGFloat = direction == .forward ? 312 : 88
        return try capture(
            window, rect: CGRect(x: center - 65, y: 72, width: 130, height: 56),
            label: "\(direction) — \(label)"
        )
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
        return Double(difference) / max(max(inkEnergy(lhs), inkEnergy(rhs)), 1)
    }

    private func inkEnergy(_ frame: RenderedFrame) -> Double {
        Double(frame.pixels.reduce(0) { $0 + Int($1) })
    }

    private func horizontalCentroid(_ frame: RenderedFrame) -> Double {
        let energy = inkEnergy(frame)
        XCTAssertGreaterThan(energy, 0)
        let moment = frame.pixels.enumerated().reduce(0) { $0 + ($1.offset % frame.width) * Int($1.element) }
        return Double(moment) / max(energy, 1)
    }

    private func assertVisible(
        _ frame: RenderedFrame, message: String = "The traveling chevron must be visible",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThan(frame.pixels.filter { $0 > 8 }.count, 20, message, file: file, line: line)
    }

    private func assertAbsent(
        _ frame: RenderedFrame, message: String = "A completed flight must leave no resting or replaying chevron",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(frame.pixels.max() ?? 0, 3, message, file: file, line: line)
    }

    private func inkBounds(_ frame: RenderedFrame, threshold: UInt8 = 128) throws -> CGRect {
        let ink = frame.pixels.indices.filter { frame.pixels[$0] > threshold }
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
