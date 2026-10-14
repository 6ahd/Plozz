import CoreModels
import Foundation
import XCTest
@testable import FeatureHomeCore

final class HeroCollectionTests: XCTestCase {
    private let selection = HeroCollectionSelection(
        accountID: "account", libraryID: "library", collectionID: "collection", title: "Favorites"
    )

    private func item(_ id: String, kind: MediaItemKind = .movie, watched: Bool = false) -> MediaItem {
        MediaItem(
            id: id, title: id, kind: kind, hasBeenPlayed: watched,
            backdropURL: URL(string: "https://example.com/\(id).jpg")
        )
    }

    private var settings: HeroSettings {
        var settings = HeroSettings.default
        settings.sources = [.collection]
        settings.collection = selection
        return settings
    }

    func testSelectionIsPartOfConfigurationOnlyWhileSourceIsEnabled() throws {
        var changed = settings
        changed.collection = .init(accountID: "other", libraryID: "library", collectionID: "collection", title: "Favorites")
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
        changed = settings
        changed.collection = .init(accountID: "account", libraryID: "library", collectionID: "different", title: "Favorites")
        XCTAssertNotEqual(HeroConfigurationKey(settings: settings), HeroConfigurationKey(settings: changed))
        changed.sources = [.watchlist]
        var disabled = changed
        disabled.collection = nil
        XCTAssertEqual(HeroConfigurationKey(settings: changed), HeroConfigurationKey(settings: disabled))
        let key = HeroConfigurationKey(settings: settings)
        XCTAssertEqual(try JSONDecoder().decode(HeroConfigurationKey.self, from: JSONEncoder().encode(key)), key)
    }

    func testShortPagesContinueInOrderWithAccountOwnership() async throws {
        let provider = CollectionProvider(items: (0..<7).map { item("\($0)") })
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 5, provider: provider, visibility: .default)
        XCTAssertEqual(result.items.map(\.id), ["0", "1", "2", "3", "4"])
        XCTAssertTrue(result.items.allSatisfy { $0.sourceAccountID == "account" })
        XCTAssertEqual(result.totalCount, 7)
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.startIndex), [0, 2, 4])
        XCTAssertEqual(requests.map(\.limit), [5, 3, 1])
    }

    func testLargeCollectionsCanSampleBeyondTheFirstWindow() async throws {
        let provider = CollectionProvider(items: (0..<100).map { item("\($0)") })
        let result = try await HeroCollectionLoader.load(
            selection: selection, limit: 4, provider: provider, visibility: .default, seed: 96
        )
        XCTAssertEqual(result.items.map(\.id), ["96", "97", "98", "99"])
        let requests = await provider.requests
        XCTAssertEqual(requests.map(\.startIndex), [0, 96, 98])
    }

    func testDisabledCollectionLibraryDoesNotFetch() async throws {
        let provider = CollectionProvider(items: [item("movie")])
        var visibility = HomeLibraryVisibility.default
        visibility.disabledKeys = [selection.libraryKey]
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: visibility)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.totalCount, 0)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testKnownHiddenMemberLibraryIsFilteredWithoutChangingItsOwnership() async throws {
        let provider = CollectionProvider(items: [
            item("hidden").taggingLibrary("hidden"), item("visible").taggingLibrary("visible")
        ])
        var visibility = HomeLibraryVisibility.default
        visibility.disabledKeys = ["account:hidden"]
        let result = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: visibility)
        XCTAssertEqual(result.items.map(\.id), ["visible"])
        XCTAssertEqual(result.items.first?.libraryID, "visible")
    }

    func testRepeatedOrFailedPagesAreNotPartialSuccess() async {
        for provider in [
            CollectionProvider(items: [item("a"), item("b"), item("c")], repeats: true),
            CollectionProvider(items: [item("a"), item("b"), item("c")], failureIndex: 2)
        ] {
            do {
                _ = try await HeroCollectionLoader.load(selection: selection, limit: 8, provider: provider, visibility: .default)
                XCTFail("A broken collection page must fail the load")
            } catch {
                XCTAssertTrue(error is AppError)
            }
        }
    }

    @MainActor
    func testUnavailableAccountCannotRestoreOrLoadSelectedCollection() async throws {
        let store = InMemoryHomeContentStore()
        store.saveHeroCandidatePool(
            .init(buckets: [.init(source: .collection, items: [item("movie").taggingSource("account")])]),
            for: HeroConfigurationKey(settings: settings)
        )
        let model = HomeViewModel(accounts: [], layoutStore: InMemoryHomeLayoutStore(), contentStore: store)
        XCTAssertNil(model.cachedHeroItems(for: settings))
        let page = try await model.heroCollectionContent(selection, limit: 8, hideWatched: false)
        XCTAssertEqual(page.totalCount, 0)
    }

    func testFreshCollectionWindowDoesNotKeepUnverifiedOldMembership() {
        let old = HeroFreshnessCandidatePool(buckets: [.init(source: .collection, items: [item("removed")])])
        let fresh = HeroFreshnessCandidatePool(buckets: [.init(source: .collection, items: [item("new")])])
        XCTAssertEqual(
            fresh.preservingUnseen(from: old, history: .init()).buckets.first?.items.map(\.id), ["new"]
        )
    }

    @MainActor
    func testDifferentServerViewerCannotRestoreOrFetchSelection() async throws {
        let provider = CollectionProvider(items: [item("movie")])
        let account = ResolvedAccount(
            account: Account(id: "account", from: provider.session),
            provider: provider, plexHomeUserID: "child"
        )
        var configured = settings
        configured.collection = .init(
            accountID: "account", libraryID: "library", collectionID: "collection",
            title: "Favorites", serverUserID: "parent"
        )
        let selection = try XCTUnwrap(configured.collection)
        let store = InMemoryHomeContentStore()
        store.saveHeroCandidatePool(
            .init(buckets: [.init(source: .collection, items: [item("movie").taggingSource("account")])]),
            for: HeroConfigurationKey(settings: configured)
        )
        let model = HomeViewModel(accounts: [account], layoutStore: InMemoryHomeLayoutStore(), contentStore: store)
        XCTAssertNil(model.cachedHeroItems(for: configured))
        let page = try await model.heroCollectionContent(selection, limit: 8, hideWatched: false)
        XCTAssertTrue(page.items.isEmpty)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCurationUsesMovieAndShowMembersAndExistingWatchRules() async {
        let members = [item("film"), item("show", kind: .series), item("episode", kind: .episode), item("seen", watched: true)]
        let result = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in MediaPage(items: members, startIndex: 0, totalCount: members.count) }
        )
        XCTAssertEqual(result.items.map(\.id), ["film", "show"])
        XCTAssertEqual(result.candidatePool.buckets.first?.source, .collection)
        XCTAssertEqual(result.durableItems.map(\.id), ["film", "show"])
    }

    func testDisabledOrUnselectedSourceDoesNotFetch() async {
        for configured in [HeroSettings.default, {
            var value = settings
            value.collection = nil
            return value
        }()] {
            _ = await HeroCurator().curateResult(
                settings: configured, continueWatching: [], watchlist: [], recentlyAdded: [],
                collectionProvider: { _, _ in
                    XCTFail("Only an enabled, selected collection should fetch")
                    throw AppError.invalidResponse
                }
            )
        }
    }

    func testEmptyCollectionIsAuthoritativeButFailureAndCancellationAreNot() async {
        let empty = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in .init(items: [], startIndex: 0, totalCount: 0) }
        )
        XCTAssertTrue(isAuthoritative(empty))
        let failed = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in throw AppError.serverUnreachable }
        )
        XCTAssertEqual(failed.collectionState, .failed(.serverUnreachable))
        XCTAssertFalse(isAuthoritative(failed))
        let cancelled = await HeroCurator().curateResult(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            collectionProvider: { _, _ in throw CancellationError() }
        )
        XCTAssertEqual(cancelled.collectionState, .idle)
        XCTAssertFalse(isAuthoritative(cancelled))
    }

    private func isAuthoritative(_ result: HeroCurationResult) -> Bool {
        HeroEmptyCuration.isAuthoritative(
            settings: settings, continueWatching: [], watchlist: [], recentlyAdded: [],
            randomLibraries: [], seerConnected: false, collectionState: result.collectionState
        )
    }
}

private actor CollectionProvider: MediaProvider {
    nonisolated let kind: ProviderKind = .jellyfin
    nonisolated let session = UserSession(
        server: MediaServer(id: "server", name: "Server", baseURL: URL(string: "https://example.com")!, provider: .jellyfin),
        userID: "user", userName: "Viewer", deviceID: "device", accessToken: "test-token"
    )
    private let items: [MediaItem]
    private let repeats: Bool
    private var failureIndex: Int?
    private(set) var requests: [PageRequest] = []

    init(items: [MediaItem], repeats: Bool = false, failureIndex: Int? = nil) {
        self.items = items
        self.repeats = repeats
        self.failureIndex = failureIndex
    }

    func collectionMembers(of collectionID: String, page: PageRequest) async throws -> MediaPage {
        try respond(page)
    }

    func collections(in libraryID: String, page: PageRequest) async throws -> MediaPage {
        try respond(page)
    }

    private func respond(_ page: PageRequest) throws -> MediaPage {
        requests.append(page)
        if failureIndex == page.startIndex { throw AppError.serverUnreachable }
        return .init(
            items: Array(items.dropFirst(repeats ? 0 : page.startIndex).prefix(min(2, page.limit))),
            startIndex: page.startIndex, totalCount: items.count
        )
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { throw AppError.notFound }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
