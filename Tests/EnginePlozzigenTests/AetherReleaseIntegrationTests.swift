import AetherEngine
import CoreModels
import XCTest
@testable import EnginePlozzigen

final class AetherReleaseIntegrationTests: XCTestCase {
    func testResolvedEngineAndSourceCreditIdentifyPinnedSubtitleFix() throws {
        XCTAssertEqual(AetherEngine.version, "7.34.1")
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "AetherEngine" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/brandomoore/AetherEngine/tree/4b7552a06c4cf646bb94eb7eb273946f8b916a70"
        ))
    }

    func testEngineLivesInItsOwnDynamicFramework() {
        let engineBundle = Bundle(for: AetherEngine.self)
        XCTAssertEqual(engineBundle.bundleURL.lastPathComponent, "AetherEngine.framework")
        XCTAssertNotEqual(engineBundle.bundleURL, Bundle.main.bundleURL)
    }

    func testNewReleaseFeaturesRemainOptIn() {
        let options = LoadOptions()
        XCTAssertEqual(options.objectAudioRendering, .off)
        XCTAssertFalse(options.progressiveSegmentDelivery)
    }

    func testTrueHDLegalCreditIncludesSourceAndBothLicenses() throws {
        let credit = try XCTUnwrap(PlozzAttributions.entries.first { $0.title == "LibTrueHD" })
        XCTAssertTrue(credit.detail.contains(
            "https://github.com/superuser404notfound/LibTrueHD/tree/2.2.0"
        ))
        XCTAssertTrue(credit.detail.contains("Quick104"))
        XCTAssertTrue(credit.detail.contains("Rainbaby"))
        XCTAssertTrue(credit.detail.contains("LibTrueHDNotices.txt"))
        XCTAssertEqual(Set(credit.licenses.map(\.label)), ["MIT", "Apache-2.0"])
    }

    func testReleasedProbeCancellationAPIIsAvailable() {
        let cancellation = ProbeCancellation()
        XCTAssertFalse(cancellation.isCancelled)
        cancellation.cancel()
        XCTAssertTrue(cancellation.isCancelled)
    }

    func testInformationalRemoteHLSTracksDoNotBecomeNonworkingMenuActions() {
        let tracks = [
            TrackInfo(id: 400_000, name: "English", codec: "aac", language: "en", channels: 2, isDefault: true),
            TrackInfo(id: 400_001, name: "French", codec: "aac", language: "fr", channels: 2, isDefault: false)
        ]
        XCTAssertTrue(PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: .remoteBypass).isEmpty)
    }

    func testSelectableRoutesKeepAudioTrackIdentityAndFlags() {
        let tracks = [
            TrackInfo(
                id: 3, name: "English", codec: "eac3", language: "en",
                channels: 6, isDefault: true, isCommentary: true, isAtmos: true
            )
        ]
        for route in [VideoRoute.loopback, .software, .audio] {
            let mapped = PlozzigenVideoEngine.selectableAudioTracks(from: tracks, route: route)
            XCTAssertEqual(mapped.map(\.id), [3])
            XCTAssertEqual(mapped.first?.language, "en")
            XCTAssertEqual(mapped.first?.channels, 6)
            XCTAssertEqual(mapped.first?.isAtmos, true)
            XCTAssertEqual(mapped.first?.isCommentary, true)
            XCTAssertEqual(mapped.first?.isDefault, true)
        }
    }
}
