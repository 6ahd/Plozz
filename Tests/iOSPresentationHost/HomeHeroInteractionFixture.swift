import CoreModels
import CoreUI
import FeatureAuth
import FeatureHomeCore
import Observation
import SwiftUI
@testable import AppShelliOS

struct HomeHeroInteractionFixture: View {
    @State private var appModel: PlozziOSAppModel
    @State private var trailer = HeroTrailerController()
    @State private var sidebar = PlozziOSSidebarGeometryModel()
    @State private var pull = PlozziOSHomeHeroPullModel()
    @State private var actions = HeroInteractionActions()
    @State private var playCount = 0

    init() {
        SyncSetupFeatureFlag().isEnabled = false
        let accounts = AccountStore(secureStore: InMemorySecureStore())
        let defaults = UserDefaults(suiteName: "HomeHeroInteractionFixture")!
        defaults.removePersistentDomain(forName: "HomeHeroInteractionFixture")
        let model = PlozziOSAppModel(accountStore: accounts, profileStore: ProfileStore(defaults: defaults))
        for kind in [ProviderKind.jellyfin, .emby] {
            let provider = HeroInteractionProvider(kind: kind)
            model.accountsProviders.registry.register(kind) { _ in provider }
            do {
                try accounts.add(provider.account, token: "fixture")
            } catch {
                fatalError("Unable to prepare hero account: \(error)")
            }
        }
        model.accountsProviders.reloadAccounts()
        model.settings.heroBackground.settings.homeTrailerEnabled = false
        model.settings.heroBackground.settings.detailMode = .off
        _appModel = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            PlozziOSHomeScrollView(heroActive: true) {
                PlozziOSHomeHeroCarousel(
                    items: HeroInteractionProvider.slides,
                    autoAdvance: false,
                    autoAdvanceSeconds: 30,
                    onPlay: { _ in playCount += 1 },
                    pullModel: pull
                )
            } rows: {
                Text("Below the hero").accessibilityIdentifier("hero-following-row")
                Color.clear.frame(height: 1_200)
            }
            .navigationTitle("Home fixture")
            .navigationBarTitleDisplayMode(.inline)
        }
        .overlay(alignment: .bottomTrailing) {
            VStack {
                Text(verbatim: "\(playCount)").accessibilityIdentifier("hero-play-count")
                Text(verbatim: "\(actions.watchlistCount)").accessibilityIdentifier("hero-watchlist-count")
            }
            .allowsHitTesting(false)
        }
        .environment(appModel)
        .environment(trailer)
        .environment(sidebar)
        .environment(\.mediaItemActionHandler, actions)
        .environment(\.plozzMetrics, .touch(density: .standard))
        .environment(\.locale, Locale(identifier: "en_US"))
        .plozziOSTracksHeroContainerHeight()
    }
}

@MainActor
@Observable
private final class HeroInteractionActions: MediaItemActionHandling {
    var watchlistCount = 0

    func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
        [.addToWatchlist]
    }

    func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {
        if action == .addToWatchlist { watchlistCount += 1 }
    }
}

private struct HeroInteractionProvider: MediaProvider {
    let kind: ProviderKind

    var account: Account {
        Account(
            id: kind.rawValue,
            server: MediaServer(
                id: kind.rawValue, name: kind.rawValue,
                baseURL: URL(string: "https://hero.invalid")!, provider: kind
            ),
            userID: "viewer", userName: "Viewer", deviceID: "fixture"
        )
    }
    var session: UserSession { account.session(token: "fixture") }

    static var slides: [MediaItem] {
        [
            MediaItem(id: "movie", title: "Hero Movie", kind: .movie).taggingSource(ProviderKind.jellyfin.rawValue),
            MediaItem(
                id: "episode", title: "Hero Episode", kind: .episode,
                parentTitle: "Hero Series", seasonNumber: 1, episodeNumber: 2, seriesID: "series"
            ).taggingSource(ProviderKind.emby.rawValue)
        ]
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: 0, totalCount: 0)
    }
    func item(id: String) async throws -> MediaItem {
        if id == "series" {
            return MediaItem(
                id: id, title: "Hero Series", kind: .series,
                overview: "Details for series from \(account.id)"
            ).taggingSource(account.id)
        }
        guard var item = Self.slides.first(where: { $0.id == id && $0.sourceAccountID == account.id }) else {
            throw AppError.notFound
        }
        item.overview = "Details for \(item.id) from \(account.id)"
        return item
    }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
