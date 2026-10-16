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

    func testForwardSpringHandoverShrinksOutgoingGrowsIncomingAndReactsToImpact() async throws {
        try await assertSpringHandover(direction: .forward)
    }

    func testBackwardSpringHandoverShrinksOutgoingGrowsIncomingAndReactsToImpact() async throws {
        try await assertSpringHandover(direction: .backward)
    }

    func testRapidForwardTapsPreserveSpringAndCoalesceToOnePendingHandover() async throws {
        try await assertRapidTapFlow(direction: .forward)
    }

    func testRapidBackwardTapsPreserveSpringAndCoalesceToOnePendingHandover() async throws {
        try await assertRapidTapFlow(direction: .backward)
    }

    func testReduceMotionRendersExactlyTwoSteadyChevronsAcrossAdditionalTaps() async throws {
        for direction in [PlayerTouchSkipDirection.forward, .backward] {
            try await withFeedback(reduceMotion: true) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(120))
                let first = try self.capture(window, direction: direction, label: "Reduce Motion first insertion")
                XCTAssertEqual(self.componentCount(first.reference), 2, "Render exactly two directional chevrons")
                try await Task.sleep(for: .milliseconds(160))
                let later = try self.capture(window, direction: direction, label: "Reduce Motion unchanged insertion")
                XCTAssertTrue(first.reference == later.reference, "The reference HUD must remain pixel-identical")
                XCTAssertTrue(first.subject == later.subject, "The subject HUD must remain pixel-identical")

                _ = fixture.subject.seek(by: interval, from: 300, within: 0...600)
                try await Task.sleep(for: .milliseconds(180))
                let repeated = try self.capture(window, direction: direction, label: "Reduce Motion additional tap")
                // Different vertical origins can rasterize differently; compare the same HUD before and after the tap.
                XCTAssertTrue(
                    later.subject == repeated.subject, "Updating the total must leave its glyph pixels unchanged"
                )
                XCTAssertEqual(fixture.subject.skip?.seconds, interval * 2)
                XCTAssertEqual(fixture.subject.skip?.direction, direction)
                try await Task.sleep(for: .milliseconds(160))
                let continued = try self.capture(window, direction: direction, label: "Reduce Motion unchanged additional tap")
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
            let stopped = try self.capture(window, direction: .forward, label: "Reduce Motion activated during spring")
            XCTAssertEqual(self.componentCount(stopped.subject), 2)
            try await Task.sleep(for: .milliseconds(180))
            let later = try self.capture(window, direction: .forward, label: "Reduce Motion activation remains static")
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
                let first = try self.capture(
                    window, direction: direction, label: "Pulse \(pulse) outgoing 60 ms", afterScreenUpdates: false
                )
                try await Task.sleep(until: startedAt + .milliseconds(180), clock: .continuous)
                let moving = try self.capture(
                    window, direction: direction, label: "Pulse \(pulse) incoming 180 ms", afterScreenUpdates: false
                )
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
                try await Task.sleep(until: startedAt + .milliseconds(700), clock: .continuous)
                let settled = try self.capture(
                    window, direction: direction, label: "Pulse \(pulse) settled 700 ms", afterScreenUpdates: false
                )
                try await Task.sleep(until: startedAt + .milliseconds(850), clock: .continuous)
                let resting = try self.capture(
                    window, direction: direction, label: "Pulse \(pulse) still held 850 ms", afterScreenUpdates: false
                )
                XCTAssertTrue(
                    settled.subject == resting.subject,
                    "The spring must settle by 700 ms and stay pixel-identical while the cumulative HUD remains visible"
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

    private func assertSpringHandover(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let glyphRenderer = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 48), format: format)
            let startedAt = ContinuousClock.now
            fixture.seek(by: direction == .forward ? 25 : -25)
            let sign = direction == .forward ? 1.0 : -1.0
            var samples: [HandoverSample] = []
            while ContinuousClock.now < startedAt + .milliseconds(450) {
                // Yield between actual display samples, even when a capture runs past its intended cadence.
                try await Task.sleep(for: .milliseconds(4))
                let sample = try self.captureGlyphROI(
                    window, direction: direction, renderer: glyphRenderer,
                    label: "Spring ROI sample \(samples.count)", elapsedSince: startedAt
                )
                samples.append(sample)
            }
            _ = try self.capture(
                window, direction: direction, label: "Spring full-context reference",
                afterScreenUpdates: false, elapsedSince: startedAt
            )
            try await Task.sleep(until: startedAt + .milliseconds(700), clock: .continuous)
            let rest = try self.captureGlyphROI(
                window, direction: direction, renderer: glyphRenderer, label: "Spring settled ROI", elapsedSince: startedAt
            ).pixels
            try await Task.sleep(until: startedAt + .milliseconds(850), clock: .continuous)
            let held = try self.captureGlyphROI(
                window, direction: direction, renderer: glyphRenderer, label: "Spring held ROI", elapsedSince: startedAt
            ).pixels
            _ = try self.capture(
                window, direction: direction, label: "Spring held full-context reference",
                afterScreenUpdates: false, elapsedSince: startedAt
            )
            XCTAssertTrue(rest == held, "The handover must finish, not loop while the count remains visible")
            XCTAssertNotNil(fixture.subject.skip, "The count must remain visible after the spring settles")
            let restingGlyphs = self.glyphRegions(rest).sorted { $0.x * sign < $1.x * sign }
            XCTAssertEqual(restingGlyphs.count, 2)
            let trailing = try XCTUnwrap(restingGlyphs.first)
            let leading = try XCTUnwrap(restingGlyphs.last)

            var distinct: [HandoverSample] = []
            for sample in samples {
                if distinct.isEmpty && sample.pixels == rest { continue }
                if let previous = distinct.last, previous.pixels == sample.pixels { continue }
                distinct.append(sample)
            }
            let measurements = samples.map { sample in
                let regions = self.glyphRegions(sample.pixels).map {
                    "x=\($0.x), width=\($0.width), height=\($0.height), ink=\($0.ink)"
                }.joined(separator: "; ")
                let rear = self.rearGlyphRegion(sample.pixels, leading: leading, direction: direction)
                    .map { "x=\($0.x), height=\($0.height), ink=\($0.ink)" } ?? "absent"
                return "\(sample.milliseconds) ms (capture \(sample.captureMilliseconds) ms): \(regions); rear behind leading slot: \(rear)"
            }.joined(separator: "\n")
            let evidence = XCTAttachment(string: measurements)
            evidence.name = "\(direction) — actual capture times and measured glyph regions"
            evidence.lifetime = .keepAlways
            self.add(evidence)
            XCTAssertGreaterThanOrEqual(distinct.count, 3, "Capture distinct displayed handover phases, not duplicate surfaces")

            // Prefer a still-separate outgoing glyph between the two home slots. Only fall back to
            // its rear stroke when merging has made connected-component identity ambiguous.
            let rearRest = try XCTUnwrap(self.rearGlyphRegion(rest, leading: leading, direction: direction))
            let maximumFullHeight: Double = Double(trailing.height) * 0.85
            let maximumOutgoingHeight: Double = Double(rearRest.height) * 0.85
            let departure = distinct.first { sample in
                let regions: [GlyphRegion] = self.glyphRegions(sample.pixels)
                let separateDeparture = regions.contains { region in
                    let advance: Double = (region.x - trailing.x) * sign
                    let distanceToLeading: Double = (leading.x - region.x) * sign
                    let shrank: Bool = Double(region.height) < maximumFullHeight
                    return advance > 1 && distanceToLeading > 0 && shrank
                }
                if separateDeparture { return true }
                guard let rear = self.rearGlyphRegion(sample.pixels, leading: leading, direction: direction) else {
                    return false
                }
                let advance: Double = (rear.x - rearRest.x) * sign
                return advance > 1 && Double(rear.height) < maximumOutgoingHeight
            }
            let departing = try XCTUnwrap(
                departure,
                "The outgoing glyph must shrink and advance between slots, using its rear stroke only when merged"
            )
            XCTAssertGreaterThan(self.difference(departing.pixels, rest), 0.12)

            // A lone leading glyph is not an incoming glyph. Require entry behind the trailing home
            // position, then follow a distinct later displayed frame as that same rear glyph grows.
            var entries: [(sample: HandoverSample, region: GlyphRegion)] = []
            for sample in distinct {
                let rearHalf = (trailing.x + leading.x) / 2
                let rear = self.glyphRegions(sample.pixels).filter { ($0.x - rearHalf) * sign < 0 }
                    .min { $0.x * sign < $1.x * sign }
                if let rear { entries.append((sample, rear)) }
            }
            let entry = try XCTUnwrap(entries.first {
                ($0.region.x - trailing.x) * sign < -1 && Double($0.region.height) < Double(trailing.height) * 0.85
            }, "Observe a genuinely small incoming glyph behind its home slot, not the remaining leading glyph")
            let grown = try XCTUnwrap(entries.first { candidate in
                let later: Bool = candidate.sample.milliseconds > entry.sample.milliseconds
                let taller: Bool = candidate.region.height > entry.region.height + 2
                let advance: Double = (candidate.region.x - entry.region.x) * sign
                let gainedInk: Bool = candidate.region.ink > entry.region.ink * 1.15
                return later && taller && advance > 1 && gainedInk
            }, "Observe a distinct later frame with incoming growth and directional entry")
            let entryEarly = entry.region
            let entryLater = grown.region
            XCTAssertLessThan(Double(entryEarly.height), Double(trailing.height) * 0.85, "The incoming glyph must begin small")
            XCTAssertGreaterThan(entryLater.height, entryEarly.height + 2, "The incoming glyph must visibly grow")
            XCTAssertGreaterThan(
                (entryLater.x - entryEarly.x) * sign, 1, "The growing incoming glyph must sweep in from behind"
            )
            XCTAssertGreaterThan(entryLater.ink, entryEarly.ink * 1.15, "The entering glyph must gain visible ink")
            XCTAssertGreaterThan(self.difference(entry.sample.pixels, rest), 0.12)
            XCTAssertGreaterThan(self.difference(entry.sample.pixels, grown.sample.pixels), 0.12)
            let impact = try XCTUnwrap(distinct.first { sample in
                guard let front = self.glyphRegions(sample.pixels).max(by: { $0.x * sign < $1.x * sign }) else {
                    return false
                }
                return front.width != leading.width || front.height != leading.height
            }, "The leading glyph must briefly change shape at impact, rather than remain an inert neighbor")
            XCTAssertGreaterThan(
                self.difference(impact.pixels, rest), 0.12, "The actual impact frame must visibly differ from rest"
            )
        }
    }

    private func assertRapidTapFlow(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Keep totals two digits so text layout cannot shift the glyph comparison.
            // Both last taps land at 180 ms, keeping their one-second HUD holds comparable.
            // The reference queues one spring; the subject receives five rapid accepted taps.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [80, 105, 130, 155, 180] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    if milliseconds == 180 {
                        _ = fixture.reference.seek(by: sign * 5, from: 300, within: 0...600)
                    }
                    _ = fixture.subject.seek(by: sign * 5, from: 300, within: 0...600)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }

            try await Task.sleep(until: startedAt + .milliseconds(50), clock: .continuous)
            let initial = try self.capture(
                window, direction: direction, label: "Burst baseline 50 ms", afterScreenUpdates: false
            )
            XCTAssertLessThan(self.difference(initial.reference, initial.subject), 0.12)
            try await Task.sleep(until: startedAt + .milliseconds(200), clock: .continuous)
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(300), "The entire burst must land during the first spring")
            let duringBurst = try self.capture(
                window, direction: direction, label: "Burst preserves active spring 200 ms", afterScreenUpdates: false
            )
            XCTAssertGreaterThan(self.difference(initial.subject, duringBurst.subject), 0.12)
            XCTAssertLessThan(
                self.difference(duringBurst.reference, duringBurst.subject), 0.12,
                "Rapid taps must preserve the original rendered phase, not restart or cancel it"
            )

            var queuedFrames: [[UInt8]] = []
            for milliseconds in [480, 540, 600, 680, 760, 840] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                let frame = try self.capture(
                    window, direction: direction, label: "Pending spring \(milliseconds) ms", afterScreenUpdates: false
                )
                queuedFrames.append(frame.subject)
                XCTAssertLessThan(
                    self.difference(frame.reference, frame.subject), 0.12,
                    "One pending handover and five coalesced taps must remain in the same rendered spring phase"
                )
            }
            let queuedMovement = zip(queuedFrames, queuedFrames.dropFirst()).map { self.difference($0.0, $0.1) }
            XCTAssertGreaterThan(
                queuedMovement.max() ?? 0, 0.12,
                "The pending spring must visibly hand over after the first spring, not be dropped or cancelled"
            )

            try await Task.sleep(until: startedAt + .milliseconds(950), clock: .continuous)
            let settled = try self.capture(
                window, direction: direction, label: "Burst settled 950 ms", afterScreenUpdates: false
            )
            try await Task.sleep(until: startedAt + .milliseconds(1100), clock: .continuous)
            let resting = try self.capture(
                window, direction: direction, label: "Burst still held 1100 ms", afterScreenUpdates: false
            )
            XCTAssertTrue(
                settled.subject == resting.subject,
                "One active spring plus one pending spring must settle by 950 ms, without a per-tap backlog or idle loop"
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

    private func captureGlyphROI(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, renderer: UIGraphicsImageRenderer,
        label: String, elapsedSince: ContinuousClock.Instant
    ) throws -> HandoverSample {
        let x: CGFloat = direction == .forward ? 325 : 15
        let capturedAt = ContinuousClock.now
        // Draw the presented window through a 60×48 viewport, not a full-window bitmap that is cropped afterward.
        let image = renderer.image { context in
            context.cgContext.translateBy(x: -x, y: -276)
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: false))
        }
        let glyphs = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 60 * 48)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 60, height: 48, bitsPerComponent: 8, bytesPerRow: 60,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            context.draw(glyphs, in: CGRect(x: 0, y: 0, width: 60, height: 48))
        }
        XCTAssertGreaterThan(pixels.filter { $0 > 80 }.count, 30, "The presented glyph ROI must contain visible ink")
        let finishedAt = ContinuousClock.now
        let elapsed = elapsedMilliseconds(from: elapsedSince, to: capturedAt)
        let duration = elapsedMilliseconds(from: capturedAt, to: finishedAt)
        let name = "\(direction) — \(label) — captured \(elapsed.formatted(.number.precision(.fractionLength(1)))) ms"
        capturedImages.append((image, name))
        return HandoverSample(milliseconds: elapsed, captureMilliseconds: duration, pixels: pixels)
    }

    private func capture(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, label: String,
        afterScreenUpdates: Bool = true, elapsedSince: ContinuousClock.Instant? = nil
    ) throws -> (reference: [UInt8], subject: [UInt8], capturedAt: ContinuousClock.Instant) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let capturedAt = ContinuousClock.now
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates))
        }
        let elapsed = elapsedSince.map {
            " — captured \(elapsedMilliseconds(from: $0, to: capturedAt).formatted(.number.precision(.fractionLength(1)))) ms"
        } ?? ""
        let name = "\(direction) — \(label)\(elapsed)"
        capturedImages.append((image, name))
        let cgImage = try XCTUnwrap(image.cgImage)
        // Isolate the glyph side of each fixed 400×200 HUD, excluding the changing total.
        let x: CGFloat = direction == .forward ? 325 : 15
        func pixels(y: CGFloat) throws -> [UInt8] {
            let crop = try XCTUnwrap(cgImage.cropping(to: CGRect(x: x, y: y, width: 60, height: 48)))
            if y == 276 {
                capturedImages.append((UIImage(cgImage: crop), "\(name) — subject glyphs"))
            }
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
        return (try pixels(y: 76), try pixels(y: 276), capturedAt)
    }

    private func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        let difference = zip(lhs, rhs).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        let energy = max(lhs.reduce(0) { $0 + Int($1) }, rhs.reduce(0) { $0 + Int($1) })
        return Double(difference) / Double(max(energy, 1))
    }

    private func componentCount(_ pixels: [UInt8]) -> Int {
        glyphRegions(pixels).count
    }

    private struct HandoverSample {
        let milliseconds: Double
        let captureMilliseconds: Double
        let pixels: [UInt8]
    }

    private struct GlyphRegion {
        let x: Double
        let minX: Int
        let maxX: Int
        let width: Int
        let height: Int
        let ink: Double
    }

    private func elapsedMilliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: end).components
        return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1_000_000_000_000_000
    }

    private func rearGlyphRegion(
        _ pixels: [UInt8], leading: GlyphRegion, direction: PlayerTouchSkipDirection
    ) -> GlyphRegion? {
        var rear = pixels
        for index in rear.indices {
            let x = index % 60
            let behindLeading = direction == .forward ? x < leading.minX : x > leading.maxX
            if !behindLeading { rear[index] = 0 }
        }
        return glyphRegions(rear).max { $0.ink < $1.ink }
    }

    private func glyphRegions(_ pixels: [UInt8]) -> [GlyphRegion] {
        var remaining = Set(pixels.indices.filter { pixels[$0] > 128 })
        var regions: [GlyphRegion] = []
        while let seed = remaining.first {
            remaining.remove(seed)
            var queue = [seed]
            var size = 0
            var weightedX = 0
            var weight = 0
            var minX = 60
            var maxX = 0
            var minY = 48
            var maxY = 0
            while let index = queue.popLast() {
                size += 1
                weightedX += (index % 60) * Int(pixels[index])
                weight += Int(pixels[index])
                minX = min(minX, index % 60)
                maxX = max(maxX, index % 60)
                minY = min(minY, index / 60)
                maxY = max(maxY, index / 60)
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
            if size > 10 {
                regions.append(GlyphRegion(
                    x: Double(weightedX) / Double(weight), minX: minX, maxX: maxX,
                    width: maxX - minX + 1, height: maxY - minY + 1, ink: Double(weight)
                ))
            }
        }
        return regions.sorted { $0.x < $1.x }
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
