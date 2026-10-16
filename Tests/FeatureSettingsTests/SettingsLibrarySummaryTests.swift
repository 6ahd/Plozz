#if os(tvOS)
import CoreModels
import CoreUI
import XCTest
@testable import FeatureSettings

@MainActor
final class SettingsLibrarySummaryTests: XCTestCase {
    func testSummaryOnlyIncludesEnabledLibrariesForTheCurrentAccounts() {
        let libraries = [
            library("movies", title: "Movies", account: "plex", provider: .plex),
            library("films", title: "Movies", account: "jellyfin", provider: .jellyfin),
            library("music", title: "Music", account: "jellyfin", provider: .jellyfin, isMusic: true),
            library("hidden", title: "Hidden", account: "plex", provider: .plex),
            library("adult", title: "Another profile", account: "excluded", provider: .jellyfin),
            library("plex:collections:movies", title: "Retired", account: "plex", provider: .plex,
                    kind: .collection)
        ]
        let visibility = HomeLibraryVisibility(disabledKeys: ["plex:hidden"])
        XCTAssertEqual(SettingsLibrariesRow.names(
            in: libraries, accountIDs: ["plex", "jellyfin"], visibility: visibility,
            locale: Locale(identifier: "en_US")
        ), ["Movies", "Music"])
        XCTAssertEqual(SettingsLibrariesRow.names(
            in: libraries, accountIDs: ["excluded"], visibility: visibility,
            locale: Locale(identifier: "en_US")
        ), ["Another profile"])
        XCTAssertEqual(SettingsLibrariesRow.names(
            in: libraries, accountIDs: [], visibility: visibility, locale: .current
        ), [])
    }

    func testSummaryUsesSynthesizedDisplayNamesWithoutTranslatingServerNames() {
        var synthesized = library("share", title: "Internal fallback", account: "share", provider: .mediaShare)
        synthesized.library.synthesizedName = .movies
        let named = library("named", title: "Family cinema", account: "share", provider: .mediaShare)
        let locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(SettingsLibrariesRow.names(
            in: [synthesized, named], accountIDs: ["share"], visibility: .default, locale: locale
        ), [synthesized.library.displayName(in: locale), "Family cinema"])
    }

    private func library(
        _ id: String, title: String, account: String, provider: ProviderKind,
        kind: MediaItemKind = .movie, isMusic: Bool = false
    ) -> AggregatedLibrary {
        AggregatedLibrary(
            accountID: account, accountName: "Viewer", serverName: "Server", providerKind: provider,
            library: MediaLibrary(id: id, title: title, kind: kind, isMusic: isMusic)
        )
    }
}
#endif
