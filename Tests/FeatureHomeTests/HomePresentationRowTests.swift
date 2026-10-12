import XCTest
import CoreModels
@testable import FeatureHomeCore

final class HomePresentationRowTests: XCTestCase {
    func testLiveOnlyHomeUsesTypedRowsAndIndependentVisibility() {
        let card = HomeLiveTVChannel(
            route: .init(
                profileID: "profile", channelID: "live", sourceID: "playlist",
                sourceAuthorizationID: "approval", serverAuthorizationID: "servers"
            ), name: "News", sourceName: "Playlist", number: 1
        )
        let snapshot = HomeLiveTVSnapshot(recentChannels: [card], channels: [card])
        let order: [HomeRowID] = [.liveTV, .global(.continueWatching)]
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: order, shown: Set(order)))
        let rows = HomePresentationRow.resolve(rows: [], content: .init(), visibility: visibility, liveTV: snapshot)
        XCTAssertEqual(rows.map(\.id), order)
        guard case .liveTV(let channels) = rows.first?.source,
              case .home(let recent) = rows.last?.source else { return XCTFail("Expected typed Live TV and mixed recent row") }
        XCTAssertEqual(channels, [card])
        XCTAssertEqual(recent.kind, .continueWatching)
        XCTAssertTrue(recent.items.isEmpty, "A live channel must never masquerade as a MediaItem.")
        if case .loaded = HomePresentationRow.displayState(.empty, liveTV: snapshot, visibility: visibility) {
        } else { XCTFail("Cached Live TV can populate an otherwise empty Home.") }

        let hidden = HomeLibraryVisibility(rowCustomization: .init(order: order, hidden: Set(order)))
        XCTAssertFalse(HomePresentationRow.hasLiveTVRows(snapshot, visibility: hidden))
        let noRecent = HomeLibraryVisibility(rowCustomization: .init(
            order: order, hidden: [.global(.continueWatching)], shown: [.liveTV]
        ))
        XCTAssertEqual(
            HomePresentationRow.resolve(rows: [], content: .init(), visibility: noRecent, liveTV: snapshot).map(\.id),
            [.liveTV]
        )
    }

    private func library(_ account: String) -> AggregatedLibrary {
        AggregatedLibrary(
            accountID: account, accountName: account, serverName: "Server",
            providerKind: .emby, library: MediaLibrary(id: "movies", title: "Movies", kind: .movie)
        )
    }

    func testEveryLayoutReceivesOneOrderedAndFilteredRowList() {
        let a = library("a")
        let b = library("b")
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let sections = [
            HomeLibrarySectionGroup(library: a, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest A", items: [item]),
                LibrarySection(id: "hidden", title: "Hidden", items: [item], isHomeDefault: false)
            ]),
            HomeLibrarySectionGroup(library: b, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest B", items: [item])
            ])
        ]
        let content = HomeViewModel.Content(
            continueWatching: [item], latest: [item], watchlist: [item], libraries: [a, b],
            mergeLibraries: false, librarySections: sections
        )
        let order: [HomeRowID] = [
            .library(b.key, kind: .recentlyAdded), .global(.watchlist),
            .library(a.key, kind: .recentlyAdded), .global(.continueWatching), .libraries
        ]
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: order))
        let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled,
                                isGlobalRowEnabled: visibility.isGlobalRowEnabled)
        let resolved = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
        XCTAssertEqual(resolved.map(\.id), order)
        XCTAssertEqual(Set(resolved.map(\.id)).count, resolved.count)
    }

    func testAllRowsCanStayHiddenIncludingLibraries() {
        let source = library("a")
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie)
        let content = HomeViewModel.Content(
            continueWatching: [item], latest: [item], watchlist: [item], libraries: [source],
            librarySections: [.init(library: source, sections: [
                LibrarySection(id: "recentlyAdded", title: "Latest", items: [item])
            ])]
        )
        let choices = HomeRowChoice.shared + HomeRowChoice.baseRows(for: source)
        let visibility = HomeLibraryVisibility(
            rowCustomization: .init(hidden: Set(choices.map(\.id)))
        )
        let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled)
        XCTAssertTrue(HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility).isEmpty)
    }

    func testSelectedRecommendationKeepsItsOrderedSlotWhileLoadingAndFailing() {
        let source = library("a")
        let id = HomeRowID.library(key: source.key, section: "selected")
        let visibility = HomeLibraryVisibility(rowCustomization: .init(order: [id, .libraries], shown: [id]))
        for failure: AppError? in [nil, .serverUnreachable] {
            let content = HomeViewModel.Content(
                libraries: [source], librarySections: [
                    .init(library: source, sections: [],
                          loadingRows: failure == nil ? [.hubs] : [],
                          failures: failure.map { [.hubs: $0] } ?? [:])
                ]
            )
            let rows = HomeRow.rows(for: content, isLibraryVisible: visibility.isEnabled)
            let result = HomePresentationRow.resolve(rows: rows, content: content, visibility: visibility)
            XCTAssertEqual(result.map(\.id), [id, .libraries])
            guard case let .library(row) = result.first?.source else {
                return XCTFail("Expected the selected recommendation's loading/error slot")
            }
            XCTAssertEqual(row.failure, failure)
            XCTAssertEqual(row.isLoading, failure == nil)
        }
    }

    func testNextUpAndLatestRetainTheirOrderAsEitherFeedCompletes() {
        let source = library("a")
        let item = MediaItem(id: "episode", title: "Episode", kind: .episode)
        for loaded in [Set<String>(), ["nextUp"], ["recentlyAdded"], ["nextUp", "recentlyAdded"]] {
            let group = HomeLibrarySectionGroup(
                library: source,
                sections: ["recentlyAdded", "nextUp"].filter(loaded.contains).map {
                    LibrarySection(id: $0, title: $0, items: [item])
                },
                loadingRows: Set([LibraryHomeRowKind.nextUp, .recentlyAdded].filter {
                    !loaded.contains($0.rawValue)
                })
            )
            XCTAssertEqual(group.rows.map(\.id), ["nextUp", "recentlyAdded"])
        }
    }
}
