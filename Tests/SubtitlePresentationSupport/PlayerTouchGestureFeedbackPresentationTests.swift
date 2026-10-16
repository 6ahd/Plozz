#if os(iOS)
import CoreUI
import Observation
import SwiftUI
import UIKit
import XCTest
@testable import FeaturePlayback

@MainActor
final class PlayerTouchGestureFeedbackPresentationTests: XCTestCase {
    private var capturedImages: [(image: UIImage, name: String)] = []
    private var glyphBackground: RenderedFrame?

    func testFirstForwardChevronTravelsHoldsFadesAndRetriggersWhileCountRemains() async throws {
        try await assertFlight(direction: .forward)
    }

    func testFirstBackwardChevronTravelsHoldsFadesAndRetriggersWhileCountRemains() async throws {
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
            try await withFeedback(direction: direction, reduceMotion: true) { fixture, window in
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
            try await withFeedback(direction: direction) { fixture, window in
                let interval: TimeInterval = direction == .forward ? 25 : -25
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(140))
                let lastPulseAt = ContinuousClock.now
                fixture.seek(by: interval)
                try await Task.sleep(for: .milliseconds(60))
                let moving = try self.captureGlyphs(window, direction: direction, label: "Before Reduce Motion")
                self.assertVisible(moving)
                fixture.reduceMotion = true
                try await Task.sleep(for: .milliseconds(80))
                let stopped = try self.captureGlyphs(window, direction: direction, label: "Reduce Motion activated")
                XCTAssertEqual(self.componentCount(stopped), 1)
                try self.assertCompactIndicator(stopped, window: window, direction: direction)
                try await Task.sleep(until: lastPulseAt + .milliseconds(1120), clock: .continuous)
                let later = try self.captureGlyphs(window, direction: direction, label: "Past both flight completions")
                XCTAssertTrue(stopped.pixels == later.pixels, "Disposed flights must not disturb the steady chevron")
                XCTAssertEqual(fixture.state.skip?.seconds, interval * 2)
            }
        }
    }

    func testSkipCapsulesContainMovingAndParkedChevronsWithNativeAndReducedGlass() async throws {
        for reducePanelGlass in [false, true] {
            if !reducePanelGlass {
                guard #available(iOS 26.0, *) else { continue }
            }
            for direction in [PlayerTouchSkipDirection.forward, .backward] {
                try await withFeedback(reducePanelGlass: reducePanelGlass) { fixture, window in
                    let interval: TimeInterval = direction == .forward ? 25 : -25
                    let startedAt = ContinuousClock.now
                    fixture.seek(by: interval)
                    var frames: [Int: RenderedFrame] = [:]
                    for milliseconds in [60, 300, 720, 1120] {
                        try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                        frames[milliseconds] = try self.captureIndicator(
                            window, direction: direction,
                            label: "\(reducePanelGlass ? "Reduced" : "Native") glass, \(milliseconds) ms"
                        )
                    }
                    let idle = try XCTUnwrap(frames[1120])
                    let capsule = try self.assertCapsule(idle, reducePanelGlass: reducePanelGlass)
                    XCTAssertEqual(capsule.height, 46, accuracy: 3)
                    XCTAssertGreaterThan(capsule.width, 110, "The capsule must include the existing count and flight slot")
                    let inset = capsule.insetBy(dx: 2, dy: 2)
                    let interior = UIBezierPath(roundedRect: inset, cornerRadius: inset.height / 2)
                    let indicatorRect = self.indicatorRect(direction: direction)
                    let glyphRect = self.glyphRect(direction: direction)
                        .offsetBy(dx: -indicatorRect.minX, dy: -indicatorRect.minY)
                    let idleGlyphs = self.cropped(idle, to: glyphRect)
                    for milliseconds in [60, 300, 720] {
                        let glyphs = self.cropped(try XCTUnwrap(frames[milliseconds]), to: glyphRect)
                        let foreground = self.removingBackground(glyphs, idleGlyphs)
                        self.assertVisible(foreground)
                        let glyphBounds = try self.inkBounds(foreground, threshold: 32)
                        XCTAssertGreaterThanOrEqual(glyphBounds.height, 14, "The actual chevron must be captured")
                        XCTAssertLessThanOrEqual(glyphBounds.width, 18, "A single native chevron must not be clipped or stretched")
                        for index in foreground.pixels.indices where foreground.pixels[index] > 32 {
                            let point = CGPoint(
                                x: glyphRect.minX + CGFloat(index % foreground.width) + 0.5,
                                y: glyphRect.minY + CGFloat(index / foreground.width) + 0.5
                            )
                            XCTAssertTrue(interior.contains(point), "The entire flight must stay inside the capsule at \(milliseconds) ms")
                        }
                    }
                    XCTAssertEqual(fixture.state.skip?.seconds, interval, "The idle capsule must retain its count")
                }
            }
        }
    }

    func testSpeedCapsuleShowsRateAndFastForwardThenDisappearsWithNativeAndReducedGlass() async throws {
        for reducePanelGlass in [false, true] {
            if !reducePanelGlass {
                guard #available(iOS 26.0, *) else { continue }
            }
            try await withFeedback(
                reducePanelGlass: reducePanelGlass, colorScheme: reducePanelGlass ? .dark : .light
            ) { fixture, window in
                fixture.state.showBoost(rate: 2)
                try await Task.sleep(for: .milliseconds(150))
                let rect = CGRect(x: 110, y: 8, width: 180, height: 64)
                let speed = try self.capture(window, rect: rect, label: "\(reducePanelGlass ? "Reduced" : "Native") glass speed pill")
                let capsule = try self.assertCapsule(speed, reducePanelGlass: reducePanelGlass)
                XCTAssertEqual(capsule.minY + rect.minY, 16, accuracy: 2, "The speed pill must respect its top inset")
                XCTAssertGreaterThanOrEqual(capsule.height, 38)
                XCTAssertLessThanOrEqual(capsule.height, 50)
                let backing = self.cropped(speed, to: CGRect(
                    x: capsule.midX - 8, y: capsule.minY + 5, width: 16, height: 2
                ))
                XCTAssertLessThanOrEqual(
                    self.inkEnergy(backing) / Double(max(backing.pixels.count, 1)), 118,
                    "White speed feedback must retain a dark capsule even when its parent uses Light appearance"
                )
                let label = self.cropped(speed, to: CGRect(
                    x: capsule.minX + 18, y: capsule.minY + 8,
                    width: capsule.width / 2 - 18, height: capsule.height - 16
                ))
                let icon = self.cropped(speed, to: CGRect(
                    x: capsule.midX + 3, y: capsule.minY + 8,
                    width: capsule.width / 2 - 21, height: capsule.height - 16
                ))
                XCTAssertEqual(self.componentCount(label, threshold: 160), 2, "The rate must render both 2 and ×")
                let iconBounds = try self.inkBounds(icon, threshold: 160)
                XCTAssertGreaterThanOrEqual(iconBounds.width, 18)
                XCTAssertGreaterThanOrEqual(iconBounds.height, 10)
                // At this size the native first triangle's tip touches the second base.
                // Verify two filled right-pointing tapers instead of raster connectivity.
                let rows = Int(iconBounds.minY)..<Int(iconBounds.maxY)
                let columns = (Int(iconBounds.minX)..<Int(iconBounds.maxX)).map { x in
                    rows.filter { icon.pixels[$0 * icon.width + x] > 160 }.count
                }
                let midpoint = columns.count / 2
                for triangle in [Array(columns.prefix(midpoint)), Array(columns.dropFirst(midpoint))] {
                    let edgeWidth = max(2, triangle.count / 4)
                    let base = Double(triangle.prefix(edgeWidth).reduce(0, +)) / Double(edgeWidth)
                    let tip = Double(triangle.suffix(edgeWidth).reduce(0, +)) / Double(edgeWidth)
                    XCTAssertGreaterThanOrEqual(
                        base, Double(iconBounds.height) * 0.75,
                        "Each fast-forward triangle must have a tall filled base on its left"
                    )
                    XCTAssertLessThanOrEqual(
                        tip, Double(iconBounds.height) * 0.35,
                        "Each fast-forward triangle must taper to its own right-pointing tip"
                    )
                }
                let filledPixels = icon.pixels.filter { $0 > 160 }.count
                XCTAssertGreaterThan(
                    Double(filledPixels) / Double(iconBounds.width * iconBounds.height), 0.4,
                    "The speed symbol must be filled fast-forward triangles, not open skip chevrons"
                )
                XCTAssertEqual(fixture.state.boostRate, 2)
                fixture.state.showBoost(rate: nil)
                try await Task.sleep(for: .milliseconds(80))
                let removed = try self.capture(window, rect: rect, label: "Speed pill removed")
                self.assertAbsent(removed, message: "Ending boost must remove both the rate and its capsule")
            }
        }
    }

    private func assertFlight(direction: PlayerTouchSkipDirection) async throws {
        try await withFeedback(direction: direction) { fixture, window in
            let interval: TimeInterval = direction == .forward ? 25 : -25
            XCTAssertNil(fixture.state.skip)
            var lastPulseAt = ContinuousClock.now
            for pulse in 1...2 {
                let startedAt = ContinuousClock.now
                lastPulseAt = startedAt
                fixture.seek(by: interval)
                var frames: [Int: RenderedFrame] = [:]
                for milliseconds in [60, 170, 300, 500, 720, 880, 1000, 1120] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    frames[milliseconds] = try self.captureGlyphs(
                        window, direction: direction, label: "Pulse \(pulse), target \(milliseconds) ms", since: startedAt
                    )
                }
                let early = try XCTUnwrap(frames[60])
                let traveling = try XCTUnwrap(frames[170])
                let parked = try XCTUnwrap(frames[300])
                let fading = try XCTUnwrap(frames[880])
                let late = try XCTUnwrap(frames[1000])
                self.assertVisible(early)
                self.assertVisible(traveling)
                self.assertVisible(parked)
                self.assertVisible(fading)
                self.assertVisible(late)
                XCTAssertEqual(self.componentCount(early), 1, "Each isolated tap must launch one open chevron")
                XCTAssertGreaterThan(self.difference(early, traveling), 0.12, "Each accepted pulse must visibly animate")
                let travel = self.horizontalCentroid(traveling) - self.horizontalCentroid(early)
                XCTAssertGreaterThan(
                    travel * (direction == .forward ? 1 : -1), 3,
                    "The chevron must translate outward, not just fade or scale in place"
                )
                let earlyEnergy = self.inkEnergy(early)
                let parkedEnergy = self.inkEnergy(parked)
                let parkedCenter = self.horizontalCentroid(parked)
                let fadingEnergy = self.inkEnergy(fading)
                let lateEnergy = self.inkEnergy(late)
                XCTAssertGreaterThan(
                    parkedEnergy, earlyEnergy * 0.85,
                    "The chevron must arrive at its parked position at full opacity"
                )
                XCTAssertLessThan(parkedEnergy, earlyEnergy * 1.15, "Travel must not grow or brighten the single glyph")
                for milliseconds in [500, 720] {
                    let held = try XCTUnwrap(frames[milliseconds])
                    XCTAssertEqual(
                        self.horizontalCentroid(held), parkedCenter, accuracy: 0.5,
                        "The chevron must stay parked throughout its half-second hold"
                    )
                    XCTAssertEqual(
                        self.inkEnergy(held), parkedEnergy, accuracy: parkedEnergy * 0.05,
                        "The chevron must stay fully opaque until its half-second hold finishes"
                    )
                }
                for frame in [fading, late] {
                    XCTAssertEqual(
                        self.horizontalCentroid(frame), parkedCenter, accuracy: 0.5,
                        "The fade must not restart or continue horizontal travel"
                    )
                }
                XCTAssertGreaterThan(
                    fadingEnergy, parkedEnergy * 0.25,
                    "The chevron must fade gradually after its parked hold"
                )
                XCTAssertLessThan(fadingEnergy, parkedEnergy * 0.97, "Fading must begin after the half-second hold")
                XCTAssertGreaterThan(lateEnergy, parkedEnergy * 0.05, "The flight must remain visible near its end")
                XCTAssertLessThan(
                    lateEnergy, fadingEnergy * 0.8,
                    "The chevron must progressively fade, not stay opaque until abrupt removal"
                )
                self.assertAbsent(try XCTUnwrap(frames[1120]))
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
        try await withFeedback(direction: direction) { fixture, window in
            let sign = direction == .forward ? 1.0 : -1.0
            let startedAt = ContinuousClock.now
            fixture.seek(by: sign * 25)
            // Two-digit totals keep text layout out of the flight geometry comparison.
            let burst = Task { @MainActor in
                var lastPulseAt = startedAt
                for milliseconds in [150, 300, 450] {
                    try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                    fixture.seek(by: sign * 5)
                    lastPulseAt = ContinuousClock.now
                }
                return lastPulseAt
            }
            defer { burst.cancel() }
            var frames: [Int: RenderedFrame] = [:]
            for milliseconds in [60, 220, 370, 520, 780] {
                try await Task.sleep(until: startedAt + .milliseconds(milliseconds), clock: .continuous)
                frames[milliseconds] = try self.captureGlyphs(
                    window, direction: direction, label: "Rapid taps, target \(milliseconds) ms", since: startedAt
                )
            }
            let lastPulseAt = try await burst.value
            XCTAssertLessThan(lastPulseAt, startedAt + .milliseconds(550), "The burst must occur during the first flight")
            let single = try XCTUnwrap(frames[60])
            self.assertVisible(single)
            let singleBounds = try self.inkBounds(single, threshold: 32)
            let parked = try XCTUnwrap(frames[780])
            self.assertVisible(parked)
            let parkedBounds = try self.inkBounds(parked, threshold: 32)
            XCTAssertLessThanOrEqual(
                parkedBounds.width, singleBounds.width + 2,
                "Finished travel must bring the parked glyphs to the same position"
            )
            // At each new tap +70 ms, the new glyph is still about 10 points behind the older
            // parked glyphs. Combined extent proves coexistence even when their pixels intersect.
            for milliseconds in [220, 370, 520] {
                let overlap = try XCTUnwrap(frames[milliseconds])
                self.assertVisible(overlap)
                let bounds = try self.inkBounds(overlap, threshold: 32)
                XCTAssertGreaterThan(
                    bounds.width, parkedBounds.width + 5,
                    "Each new moving glyph must coexist with older parked glyphs at \(milliseconds) ms"
                )
                let outerEdge = direction == .forward ? bounds.maxX : bounds.minX
                let parkedEdge = direction == .forward ? parkedBounds.maxX : parkedBounds.minX
                XCTAssertEqual(
                    outerEdge, parkedEdge, accuracy: 3,
                    "A new tap must not pull the older glyph back from its parked position"
                )
            }
            var completionFrames: [Int: RenderedFrame] = [:]
            for milliseconds in [670, 830, 980] {
                try await Task.sleep(until: lastPulseAt + .milliseconds(milliseconds), clock: .continuous)
                let frame = try self.captureGlyphs(
                    window, direction: direction, label: "Independent completions, target \(milliseconds) ms", since: lastPulseAt
                )
                completionFrames[milliseconds] = frame
                self.assertVisible(frame, message: "Earlier completions must not remove the last flight")
                XCTAssertEqual(
                    self.horizontalCentroid(frame), self.horizontalCentroid(parked), accuracy: 0.5,
                    "Surviving glyphs must remain parked while older flights finish"
                )
            }
            let heldEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[670]))
            let fadingEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[830]))
            let lastEnergy = self.inkEnergy(try XCTUnwrap(completionFrames[980]))
            XCTAssertGreaterThan(
                heldEnergy, self.inkEnergy(parked) * 0.85,
                "The last glyph must retain its full hold after the first flight completes"
            )
            XCTAssertLessThan(
                lastEnergy, fadingEnergy * 0.8,
                "Older parked copies must fade independently instead of restarting their lifetime on every tap"
            )
            try await Task.sleep(until: lastPulseAt + .milliseconds(1120), clock: .continuous)
            let tail = try self.captureGlyphs(
                window, direction: direction, label: "Burst tail, target 1120 ms", since: lastPulseAt
            )
            self.assertAbsent(tail, message: "All flights must disappear without replay before the count expires")
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

    private func assertCapsule(_ frame: RenderedFrame, reducePanelGlass: Bool) throws -> CGRect {
        let bounds = try inkBounds(frame, threshold: 12)
        XCTAssertGreaterThan(bounds.width, 90, "Feedback must have a padded surface, not just bare foreground")
        XCTAssertLessThanOrEqual(bounds.width, 160)
        XCTAssertGreaterThanOrEqual(bounds.height, 38)
        XCTAssertLessThanOrEqual(bounds.height, 54)
        let corner = cropped(frame, to: CGRect(x: bounds.minX + 1, y: bounds.minY + 1, width: 2, height: 2))
        assertAbsent(corner, message: "The feedback surface must have capsule corners rather than a rectangular fill")
        let interior = cropped(frame, to: CGRect(x: bounds.midX - 8, y: bounds.minY + 5, width: 16, height: 2))
        XCTAssertGreaterThan(
            inkEnergy(interior) / Double(max(interior.pixels.count, 1)), 4,
            reducePanelGlass
                ? "Reduced glass must render the shared frosted surface behind the foreground"
                : "Native glass interior was not captured by drawHierarchy; a border alone is not native-glass evidence"
        )
        return bounds
    }

    private func withFeedback(
        direction: PlayerTouchSkipDirection? = nil, reduceMotion: Bool = false, reducePanelGlass: Bool = true,
        colorScheme: ColorScheme = .dark,
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
        let fixture = FeedbackFixture(
            reduceMotion: direction == nil ? reduceMotion : false,
            reducePanelGlass: reducePanelGlass, colorScheme: colorScheme
        )
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
            glyphBackground = nil
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        if let direction {
            // Use the real idle pill as the contrast reference. The phase/overlap tests exercise
            // the supported deterministic frosted path; native glass gets separate rendered coverage.
            fixture.seek(by: direction == .forward ? 25 : -25)
            try await Task.sleep(for: .milliseconds(1120))
            let background = try capture(
                window, rect: glyphRect(direction: direction), label: "\(direction) — idle pill contrast reference"
            )
            XCTAssertLessThanOrEqual(
                background.pixels.max() ?? 0, 96,
                "The idle frosted reference must not contain a resting white chevron"
            )
            glyphBackground = background
            fixture.state.cancel()
            fixture.state = PlayerTouchGestureState()
            fixture.reduceMotion = reduceMotion
            try await Task.sleep(for: .milliseconds(60))
        }
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
        let frame = try capture(
            window, rect: glyphRect(direction: direction), label: "\(direction) — \(label)", since: since
        )
        return glyphBackground.map { removingBackground(frame, $0) } ?? frame
    }

    private func glyphRect(direction: PlayerTouchSkipDirection) -> CGRect {
        CGRect(x: direction == .forward ? 325 : 15, y: 76, width: 60, height: 48)
    }

    private func indicatorRect(direction: PlayerTouchSkipDirection) -> CGRect {
        let center: CGFloat = direction == .forward ? 312 : 88
        return CGRect(x: center - 85, y: 64, width: 170, height: 72)
    }

    private func captureIndicator(
        _ window: UIWindow, direction: PlayerTouchSkipDirection, label: String
    ) throws -> RenderedFrame {
        return try capture(
            window, rect: indicatorRect(direction: direction),
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

    private func removingBackground(_ frame: RenderedFrame, _ background: RenderedFrame) -> RenderedFrame {
        XCTAssertEqual(frame.width, background.width)
        XCTAssertEqual(frame.height, background.height)
        let pixels = zip(frame.pixels, background.pixels).map { pixel, base -> UInt8 in
            let contrast = Int(pixel) - Int(base)
            guard contrast > 2, base < 255 else { return 0 }
            return UInt8(min(255, contrast * 255 / (255 - Int(base))))
        }
        return RenderedFrame(width: frame.width, height: frame.height, pixels: pixels)
    }

    private func cropped(_ frame: RenderedFrame, to rect: CGRect) -> RenderedFrame {
        let minX = max(0, min(frame.width, Int(rect.minX.rounded(.down))))
        let minY = max(0, min(frame.height, Int(rect.minY.rounded(.down))))
        let maxX = max(minX, min(frame.width, Int(rect.maxX.rounded(.up))))
        let maxY = max(minY, min(frame.height, Int(rect.maxY.rounded(.up))))
        var pixels: [UInt8] = []
        for y in minY..<maxY {
            pixels.append(contentsOf: frame.pixels[(y * frame.width + minX)..<(y * frame.width + maxX)])
        }
        return RenderedFrame(width: maxX - minX, height: maxY - minY, pixels: pixels)
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

    private func componentCount(_ frame: RenderedFrame, threshold: UInt8 = 128) -> Int {
        var remaining = Set(frame.pixels.indices.filter { frame.pixels[$0] > threshold })
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
    var state = PlayerTouchGestureState()
    var reduceMotion: Bool
    let reducePanelGlass: Bool
    let colorScheme: ColorScheme

    init(reduceMotion: Bool, reducePanelGlass: Bool, colorScheme: ColorScheme) {
        self.reduceMotion = reduceMotion
        self.reducePanelGlass = reducePanelGlass
        self.colorScheme = colorScheme
    }

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
            .environment(\.colorScheme, fixture.colorScheme)
            .environment(\.plozzReducePanelGlass, fixture.reducePanelGlass)
            .ignoresSafeArea()
    }
}
#endif
