import XCTest
@testable import CoreModels

final class HeroLogoSizeTests: XCTestCase {
    func testBoundedStepsStartAtCurrentSizeAndOnlyGrow() throws {
        XCTAssertEqual(HeroLogoSize.default.scale, 1)
        XCTAssertEqual(HeroLogoSize.allSizes.count, 11)
        XCTAssertEqual(HeroLogoSize(rawValue: -100), .default)
        XCTAssertEqual(HeroLogoSize(rawValue: 100).scale, 1.5)
        for (index, size) in HeroLogoSize.allSizes.enumerated() {
            XCTAssertEqual(size.scale, 1 + Double(index) * 0.05, accuracy: 0.0001)
            XCTAssertEqual(try JSONDecoder().decode(HeroLogoSize.self, from: JSONEncoder().encode(size)), size)
        }
        XCTAssertEqual(try JSONDecoder().decode(HeroLogoSize.self, from: Data("200".utf8)).rawValue, 10)
        XCTAssertThrowsError(try JSONDecoder().decode(HeroLogoSize.self, from: Data("\"invalid\"".utf8)))
    }

    func testLegacySettingsRetainCurrentSizesAndOtherChoices() throws {
        let home = try JSONDecoder().decode(
            HeroSettings.self, from: Data(#"{"maxItems":3,"autoAdvance":false,"style":"followsFocus"}"#.utf8)
        )
        XCTAssertEqual(home.logoSize, .default)
        XCTAssertEqual(home.showcaseLogoSize, .default)
        XCTAssertEqual(home.maxItems, 3)
        XCTAssertFalse(home.autoAdvance)
        let detail = try JSONDecoder().decode(
            DetailPageSettings.self, from: Data(#"{"showsHeaderRatings":false,"maxHeaderRatings":4}"#.utf8)
        )
        XCTAssertEqual(detail.logoSize, .default)
        XCTAssertFalse(detail.showsHeaderRatings)
        XCTAssertEqual(detail.maxHeaderRatings, 4)
    }

    @MainActor
    func testEachSurfacePersistsIndependentlyAcrossProfilesAndTransfer() throws {
        let suite = "HeroLogoSizeTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let home = HeroSettingsModel(store: HeroSettingsStore(defaults: defaults))
        let detail = DetailPageSettingsModel(store: DetailPageSettingsStore(defaults: defaults))
        home.settings.logoSize = HeroLogoSize(rawValue: 3)
        home.settings.showcaseLogoSize = HeroLogoSize(rawValue: 8)
        detail.settings.logoSize = HeroLogoSize(rawValue: 6)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults).load().logoSize.rawValue, 3)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults).load().showcaseLogoSize.rawValue, 8)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults).load().logoSize.rawValue, 6)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load().logoSize, .default)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults, namespace: "other").load().logoSize, .default)
        let captured = ProfileSettingsTransfer.capture(namespace: nil, defaults: defaults)
        ProfileSettingsTransfer.apply(captured, namespace: "other", defaults: defaults)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load(), home.settings)
        XCTAssertEqual(DetailPageSettingsStore(defaults: defaults, namespace: "other").load(), detail.settings)
        home.settings.logoSize = .default
        XCTAssertEqual(home.settings.showcaseLogoSize.rawValue, 8)
        XCTAssertEqual(detail.settings.logoSize.rawValue, 6)
        XCTAssertEqual(HeroSettingsStore(defaults: defaults, namespace: "other").load().logoSize.rawValue, 3)
    }
}
