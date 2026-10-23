#if canImport(UIKit)
import CoreModels
import Observation
import UIKit
import XCTest
@testable import FeatureHome

@MainActor
final class HeroForegroundRatingsStateTests: XCTestCase {
    func testPersistentForegroundScalesTextAndBordersWithoutMovingOrResizingButtons() throws {
        let foreground = HeroForegroundUIView(frame: CGRect(x: 0, y: 0, width: 1500, height: 850))
        defer { foreground.stopContinuousUpdates() }
        foreground.apply(HeroForegroundModel(
            itemID: "size-fixture", title: "NORTHSTAR", logoURL: nil,
            metadataText: "Drama", ratingBadgeText: "PG", scheduleLine: "Upcoming",
            overview: String(repeating: "An expedition beyond the stars. ", count: 20), ratings: [], familyGuidanceAge: nil,
            pills: [.init(kind: .play, text: "Play", systemImage: "play.fill", progress: nil)],
            selectedIndex: 0, heroFocused: false, dots: nil
        ), logo: nil, metadataVisible: true, slideChanged: false)
        foreground.layoutIfNeeded()
        let labels = foreground.subviews.compactMap { $0 as? UILabel }
        let certificate = try XCTUnwrap(labels.first { $0.text == "PG" })
        let description = try XCTUnwrap(labels.first { $0.text?.hasPrefix("An expedition beyond the stars.") == true })
        let metadata = try XCTUnwrap(labels.first { $0.text == "Drama" })
        let schedule = try XCTUnwrap(labels.first { $0.text == "Upcoming" })
        let title = try XCTUnwrap(labels.first { $0.text == "NORTHSTAR" })
        let pills = try XCTUnwrap(foreground.subviews.first { $0.subviews.contains { $0 is HeroForegroundPillView } })
        let buttonsFrame = pills.frame
        for rawValue in [-5, 5, 0] {
            foreground.textSize = HeroTextSize(rawValue: rawValue)
            foreground.layoutIfNeeded()
            let scale = CGFloat(foreground.textSize.scale)
            XCTAssertEqual(description.font.pointSize, 22 * scale)
            XCTAssertEqual(description.numberOfLines, rawValue > 0 ? 4 : 3)
            XCTAssertEqual(description.frame.height,
                           description.font.lineHeight * CGFloat(description.numberOfLines), accuracy: 1)
            XCTAssertEqual(metadata.font.pointSize, 23 * scale)
            XCTAssertEqual(title.font.pointSize, 64 * scale)
            XCTAssertEqual(certificate.font.pointSize, 18 * scale)
            XCTAssertEqual(certificate.layer.borderWidth, 3 * scale)
            XCTAssertEqual(certificate.frame.height, 36 * scale)
            XCTAssertEqual(schedule.font.pointSize, 24 * scale)
            XCTAssertEqual(schedule.frame.height, 52 * scale)
            XCTAssertEqual(pills.frame, buttonsFrame)
            XCTAssertGreaterThanOrEqual(schedule.frame.minY, 0)
            XCTAssertLessThanOrEqual(metadata.frame.maxY, description.frame.minY)
        }
    }

    func testAgeOnlyUpdatesPublishAndClearWithoutAReviewScoreChange() async {
        let state = HeroForegroundRatingsState()
        let update = expectation(description: "Age metadata publishes")
        withObservationTracking {
            _ = state.familyGuidanceAge
        } onChange: {
            update.fulfill()
        }
        state.update([], familyGuidanceAge: 14)
        await fulfillment(of: [update], timeout: 0.1)
        XCTAssertEqual(state.familyGuidanceAge, 14)
        state.update([])
        XCTAssertNil(state.familyGuidanceAge, "A different slide or hidden ratings clears the age.")
        state.update([], familyGuidanceAge: 14)
        let unchanged = expectation(description: "Unchanged age does not publish")
        unchanged.isInverted = true
        withObservationTracking {
            _ = state.familyGuidanceAge
        } onChange: {
            unchanged.fulfill()
        }
        for _ in 0..<100 { state.update([], familyGuidanceAge: 14) }
        await fulfillment(of: [unchanged], timeout: 0.05)
    }

    func testFocusAndDwellReapplicationsDoNotInvalidateRatings() async {
        let state = HeroForegroundRatingsState()
        let ratings = [ExternalRating(source: .imdb, value: 8, scale: .outOfTen)]
        state.update(ratings)
        let invalidation = expectation(description: "Unchanged ratings must not rebuild")
        invalidation.isInverted = true
        withObservationTracking {
            _ = state.ratings
        } onChange: {
            invalidation.fulfill()
        }

        for _ in 0..<100 { state.update(ratings) }

        await fulfillment(of: [invalidation], timeout: 0.05)
        XCTAssertEqual(state.ratings, ratings)
    }

    func testRatingUpdatesStillInvalidateAndPreserveOrder() async {
        let state = HeroForegroundRatingsState()
        let invalidation = expectation(description: "New ratings publish")
        withObservationTracking {
            _ = state.ratings
        } onChange: {
            invalidation.fulfill()
        }
        let ratings = [
            ExternalRating(source: .imdb, value: 8, scale: .outOfTen),
            ExternalRating(source: .rottenTomatoes, value: 92, scale: .percent)
        ]
        state.update(ratings)
        await fulfillment(of: [invalidation], timeout: 0.1)
        XCTAssertEqual(state.ratings, ratings)

        state.update([])
        XCTAssertTrue(state.ratings.isEmpty, "Spoiler or slide changes must clear old ratings")
    }
}
#endif
