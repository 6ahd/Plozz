import XCTest
@testable import CoreModels

final class HomeRowCustomizationTests: XCTestCase {
    private func library(
        _ account: String, _ id: String, provider: ProviderKind = .emby, kind: MediaItemKind = .movie
    ) -> AggregatedLibrary {
        AggregatedLibrary(
            accountID: account, accountName: account, serverName: "Server",
            providerKind: provider, library: MediaLibrary(id: id, title: id, kind: kind)
        )
    }

    func testBothPresetsPlaceLibrariesAfterLiveTVAndDiscoveredFallbackRows() {
        let fallback = library("a", "movies")
        let fallbackID = HomeRowID.library(fallback.key, kind: .recentlyAdded)
        let choices = HomeRowChoice.shared + HomeRowChoice.baseRows(for: fallback)
        var single = HomeRowCustomization(defaults: .matchServer)
        single.resolvedDefaults = .init(
            mode: .server, order: [.libraries, .global(.continueWatching), .liveTV]
        )
        var multiple = HomeRowCustomization(defaults: .matchServer)
        multiple.resolvedDefaults = .init(
            mode: .combined, order: HomeRowChoice.shared.map(\.id), fallbackAccountIDs: ["a"]
        )
        var unsupported = HomeRowCustomization(defaults: .matchServer)
        unsupported.resolvedDefaults = .init(mode: .providerFallback)
        let common: [HomeRowID] = [
            .global(.continueWatching), .global(.watchlist), .global(.recentlyAdded), .liveTV
        ]
        let cases: [(HomeRowCustomization, [HomeRowID])] = [
            (.init(defaults: .combined), common + [.libraries]),
            (single, [.global(.continueWatching), .liveTV, .libraries]),
            (multiple, common + [fallbackID, .libraries]),
            (unsupported, [.global(.continueWatching), .global(.watchlist), fallbackID, .libraries]),
            (.init(defaults: .matchServer),
             [.global(.continueWatching), .global(.watchlist), fallbackID, .libraries])
        ]
        for (customization, expected) in cases {
            let visibility = HomeLibraryVisibility(rowCustomization: customization)
            XCTAssertEqual(visibility.rowSections(choices: choices).enabled, expected)
            XCTAssertEqual(customization.sections(choices: choices).enabled, expected)
        }
    }

    func testLibrariesCanBeMovedOrHiddenAfterEitherPresetAndKeepThatChoice() throws {
        for preset: HomeRowCustomization.Defaults in [.matchServer, .combined] {
            var visibility = HomeLibraryVisibility(rowCustomization: .init(defaults: preset))
            let choices = HomeRowChoice.shared
            var sections = visibility.rowSections(choices: choices)
            XCTAssertEqual(sections.enabled.last, .libraries)
            sections.enabled.removeAll { $0 == .libraries }
            sections.enabled.insert(.libraries, at: 0)
            visibility.applyRows(sections, choices: choices)
            XCTAssertEqual(visibility.rowCustomization?.defaults, .custom)
            let restored = try JSONDecoder().decode(
                HomeLibraryVisibility.self, from: JSONEncoder().encode(visibility)
            )
            XCTAssertEqual(restored.rowSections(choices: choices).enabled, sections.enabled)
            sections.enabled.removeFirst()
            sections.disabled.append(.libraries)
            visibility.applyRows(sections, choices: choices)
            XCTAssertEqual(visibility.rowSections(choices: choices), sections)
        }
    }

    func testVisibilityEditFreezesThePresentedPresetOrderInsteadOfServerLibraryPosition() {
        var customization = HomeRowCustomization(defaults: .matchServer)
        customization.resolvedDefaults = .init(
            mode: .server, order: [.libraries, .global(.continueWatching), .liveTV]
        )
        customization.setVisible(false, for: .global(.continueWatching))
        XCTAssertEqual(customization.defaults, .custom)
        XCTAssertEqual(customization.sections(choices: HomeRowChoice.shared).enabled, [.liveTV, .libraries])
    }

    func testDefaultLibraryPositionDoesNotEnableAServerHiddenLibraryRowOrRewriteOldOrders() {
        var matched = HomeRowCustomization(defaults: .matchServer)
        matched.resolvedDefaults = .init(mode: .server, order: [.global(.continueWatching)])
        XCTAssertEqual(matched.sections(choices: HomeRowChoice.shared).enabled, [.global(.continueWatching)])
        for preset: HomeRowCustomization.Defaults in [.custom, .combined, .legacy, .provider] {
            let saved = HomeRowCustomization(
                defaults: preset, order: [.libraries, .global(.continueWatching)],
                shown: [.libraries, .global(.continueWatching)]
            )
            XCTAssertEqual(saved.sections(choices: HomeRowChoice.shared).enabled.first, .libraries)
        }
    }

    func testProviderDefaultsOfferLatestAndNextUpButNotMediaBrowserRecommendations() {
        let visibility = HomeLibraryVisibility.default
        let movies = library("a", "movies")
        let shows = library("a", "shows", kind: .series)
        XCTAssertEqual(visibility.requestedRowKinds(for: movies), [.recentlyAdded])
        XCTAssertEqual(visibility.requestedRowKinds(for: shows), [.nextUp, .recentlyAdded])
        XCTAssertEqual(
            visibility.requestedRowKinds(for: library("b", "movies", provider: .plex)),
            [.recentlyAdded, .hubs]
        )
        XCTAssertEqual(
            LibraryHomeRowKind.available(for: library("a", "files", provider: .mediaShare)),
            [.recentlyAdded]
        )
        XCTAssertFalse(visibility.isGlobalRowEnabled(.recentlyAdded))
        XCTAssertTrue(visibility.separatesNextUp)
    }

    func testOneOrderFreelyMixesSharedAndIndividualRowsAcrossLibraries() {
        let a = library("a", "movies")
        let b = library("b", "shows", kind: .series)
        let choices = HomeRowChoice.shared + HomeRowChoice.baseRows(for: a) + HomeRowChoice.baseRows(for: b)
        let order: [HomeRowID] = [
            .library(b.key, kind: .recentlyAdded), .global(.continueWatching),
            .library(a.key, kind: .recentlyAdded), .libraries, .library(b.key, kind: .nextUp),
            .global(.watchlist)
        ]
        var visibility = HomeLibraryVisibility.default
        visibility.applyRows(.init(enabled: order, disabled: [.global(.recentlyAdded)]), choices: choices)
        XCTAssertEqual(visibility.rowSections(choices: choices).enabled, order)
    }

    func testHiddenRecommendationSurvivesAChangedHeading() {
        let source = library("a", "movies")
        let id = HomeRowID.library(key: source.key, section: "recommendation:similar:0")
        var visibility = HomeLibraryVisibility.default
        visibility.rowCustomization?.setVisible(false, for: id)
        let renamed = HomeRowChoice(
            id: id, title: "A new recommendation", library: source, isProviderDefault: true
        )
        XCTAssertFalse(visibility.isHomeRowVisible(renamed))
    }

    func testOfflineRowsKeepPositionAndVisibilityWhenAnotherDeviceEditsItsAvailableRows() {
        let a = library("a", "movies")
        let b = library("b", "movies")
        let aID = HomeRowID.library(a.key, kind: .recentlyAdded)
        let bID = HomeRowID.library(b.key, kind: .recentlyAdded)
        var visibility = HomeLibraryVisibility(
            rowCustomization: .init(order: [aID, bID, .libraries], hidden: [bID])
        )
        let online = HomeRowChoice.baseRows(for: a) + HomeRowChoice.shared.filter { $0.id == .libraries }
        visibility.applyRows(.init(enabled: [.libraries, aID], disabled: []), choices: online)
        XCTAssertEqual(visibility.rowCustomization?.order, [.libraries, bID, aID])
        XCTAssertEqual(visibility.rowCustomization?.hidden, [bID])
        let reconnected = online + HomeRowChoice.baseRows(for: b)
        XCTAssertEqual(visibility.rowSections(choices: reconnected).disabled, [bID])
    }

    func testLegacyAllOffAndOfflineFamilyChoicesSurviveFirstFlatEdit() throws {
        let data = Data("""
        {"mergeLibrariesOnHome":false,"disabledKeys":[],
         "disabledGlobalHomeRows":["continueWatching","watchlist","recentlyAdded"],
         "enabledLibraryHomeRows":["offline:movies:recentlyAdded"],"hasSeededLibraryRows":true}
        """.utf8)
        var visibility = try JSONDecoder().decode(HomeLibraryVisibility.self, from: data)
        XCTAssertNil(visibility.rowCustomization)
        let choices = HomeRowChoice.shared
        visibility.applyRows(.init(enabled: [], disabled: choices.map(\.id)), choices: choices)
        XCTAssertEqual(visibility.rowCustomization?.defaults, .legacy)
        XCTAssertTrue(visibility.rowSections(choices: choices).enabled.isEmpty)
        XCTAssertEqual(
            visibility.requestedRowKinds(for: library("offline", "movies")),
            [.recentlyAdded]
        )
    }

    func testExplicitlyShowingOneEmbyRecommendationDoesNotEnableItsSiblings() {
        let source = library("a", "movies")
        let one = HomeRowChoice(
            id: .library(key: source.key, section: "one"), title: "One",
            library: source, isProviderDefault: false
        )
        let two = HomeRowChoice(
            id: .library(key: source.key, section: "two"), title: "Two",
            library: source, isProviderDefault: false
        )
        var visibility = HomeLibraryVisibility.default
        let base = HomeRowChoice.baseRows(for: source)
        let defaults = visibility.rowSections(choices: base)
        visibility.applyRows(
            .init(enabled: defaults.enabled + [one.id], disabled: defaults.disabled + [two.id]),
            choices: base + [one, two]
        )
        XCTAssertTrue(visibility.isHomeRowVisible(one))
        XCTAssertFalse(visibility.isHomeRowVisible(two))
        XCTAssertEqual(visibility.requestedRowKinds(for: source), [.recentlyAdded, .hubs])
    }

    func testHidingEveryKnownPlexRecommendationStopsItsRequests() {
        let source = library("a", "movies", provider: .plex)
        let ids = ["one", "two"].map { HomeRowID.library(key: source.key, section: $0) }
        let visibility = HomeLibraryVisibility(
            rowCustomization: .init(order: ids, hidden: Set(ids))
        )
        XCTAssertEqual(visibility.requestedRowKinds(for: source), [.recentlyAdded])
    }

    func testDisabledLibraryNeverFetchesEvenAnExplicitlyShownRow() {
        let source = library("a", "movies")
        let visibility = HomeLibraryVisibility(
            disabledKeys: [source.key],
            rowCustomization: .init(shown: [.library(key: source.key, section: "suggested")])
        )
        XCTAssertTrue(visibility.requestedRowKinds(for: source).isEmpty)
    }

    func testTypedIdentitiesCannotCollideWhenServerIDsContainSeparators() {
        let a = HomeRowID.library(key: "a-b", section: "c")
        let b = HomeRowID.library(key: "a", section: "b-c")
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.presentationID, b.presentationID)
    }

    func testSavedVisibilityEncodesDeterministicallyAfterEveryDecode() throws {
        let ids: [HomeRowID] = [
            .libraries, .global(.watchlist), .library(key: "a:movies", section: "one"),
            .library(key: "b:movies", section: "two")
        ]
        let value = HomeLibraryVisibility(
            disabledKeys: ["x", "y", "z"],
            rowCustomization: .init(order: ids, hidden: Set(ids))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expected = try encoder.encode(value)
        for _ in 0..<20 {
            let decoded = try JSONDecoder().decode(HomeLibraryVisibility.self, from: expected)
            XCTAssertEqual(try encoder.encode(decoded), expected)
        }
    }

    @MainActor
    func testArrangementPersistsAndTransfersOnlyWithItsProfile() throws {
        let sourceSuite = "HomeRows-source-\(UUID())"
        let targetSuite = "HomeRows-target-\(UUID())"
        let source = try XCTUnwrap(UserDefaults(suiteName: sourceSuite))
        let target = try XCTUnwrap(UserDefaults(suiteName: targetSuite))
        defer {
            source.removePersistentDomain(forName: sourceSuite)
            target.removePersistentDomain(forName: targetSuite)
        }
        let model = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: source, namespace: "one"))
        let choices = HomeRowChoice.shared
        model.applyRows(
            .init(enabled: [.libraries, .global(.continueWatching)],
                  disabled: [.global(.watchlist), .global(.recentlyAdded)]),
            choices: choices
        )
        let entries = ProfileSettingsTransfer.capture(namespace: "one", defaults: source)
        ProfileSettingsTransfer.apply(entries, namespace: "one", defaults: target)
        let restored = HomeLibraryVisibilityStore(defaults: target, namespace: "one").load()
        XCTAssertEqual(restored, model.visibility)
        XCTAssertEqual(HomeLibraryVisibilityStore(defaults: target, namespace: "two").load(), .default)
        XCTAssertEqual(
            ProfileSettingsTransfer.capture(namespace: "one", defaults: target), entries
        )
    }
}
