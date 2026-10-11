#if DEBUG
import CoreModels
import XCTest

@testable import FeaturePlayback

final class LiveChannelTimelineLayoutTests: XCTestCase {
    private let ten = Date(timeIntervalSince1970: 36_000)

    private func program(_ startHour: Double, _ endHour: Double) -> LiveChannelProgramInfo {
        LiveChannelProgramInfo(
            title: "P", start: Date(timeIntervalSince1970: startHour * 3_600),
            end: Date(timeIntervalSince1970: endHour * 3_600)
        )
    }

    func testWithoutAWindowTheBarMeasuresTheProgramme() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            seekWindowSeconds: nil, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, ten)
        XCTAssertEqual(layout.boundaries, [])
        XCTAssertNil(layout.seekableStart)
        XCTAssertEqual(layout.aired, 0.5, accuracy: 0.0001)
        XCTAssertEqual(layout.playing, 0.5, accuracy: 0.0001)
    }

    func testWindowReachesBackIntoEarlierProgrammes() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            earlierPrograms: [program(8, 9), program(9, 10)],
            seekWindowSeconds: 7_200, behindLiveSeconds: 1_800
        )
        // 08:00–11:00, split at 09:00 and 10:00, seekable from 08:30.
        XCTAssertEqual(layout.start, Date(timeIntervalSince1970: 8 * 3_600))
        XCTAssertEqual(layout.boundaries.count, 2)
        XCTAssertEqual(layout.boundaries[0], 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.boundaries[1], 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(layout.seekableStart), 1.0 / 6, accuracy: 0.0001)
        XCTAssertEqual(layout.aired, 2.5 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.playing, 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(layout.maskRanges.count, 1)
    }

    func testWindowPastTheGuideRunsOnToTheWindowStart() {
        let layout = LiveChannelTimelineLayout(
            now: ten.addingTimeInterval(1_800), program: program(10, 11),
            seekWindowSeconds: 7_200, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, ten.addingTimeInterval(-5_400))
        XCTAssertEqual(layout.boundaries.count, 1)
        XCTAssertEqual(try XCTUnwrap(layout.seekableStart), 0, accuracy: 0.0001)
    }

    func testVeryDeepWindowIsCappedToTheLookback() {
        let now = ten.addingTimeInterval(1_800)
        let layout = LiveChannelTimelineLayout(
            now: now, program: program(10, 11),
            seekWindowSeconds: 24 * 3_600, behindLiveSeconds: 0
        )
        XCTAssertEqual(layout.start, now.addingTimeInterval(-LiveChannelTimelineLayout.maximumLookback))
    }

    func testWindowWithoutGuideFillsToTheEdge() {
        let layout = LiveChannelTimelineLayout(
            now: ten, program: nil, seekWindowSeconds: 600, behindLiveSeconds: 150
        )
        XCTAssertEqual(layout.start, ten.addingTimeInterval(-600))
        XCTAssertEqual(layout.aired, 1)
        XCTAssertEqual(layout.playing, 0.75, accuracy: 0.0001)
    }
}
#endif
