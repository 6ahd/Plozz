import CoreModels
import Foundation
import XCTest
@testable import FeatureSettings

final class HeroCollectionPickerTests: XCTestCase {
    @MainActor
    func testPaginatesAndReportsRetryableErrorsWithoutLosingRows() async {
        let provider = PickerProvider()
        let model = HeroCollectionListModel(provider: provider, libraryID: "library")
        await model.loadNextPage()
        XCTAssertEqual(model.items.map(\.id), ["0", "1"])
        XCTAssertTrue(model.hasMore)
        await model.loadNextPage()
        XCTAssertEqual(model.error, .serverUnreachable)
        XCTAssertEqual(model.items.count, 2)
        await provider.setFailure(false)
        await model.loadNextPage()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.items.map(\.id), ["0", "1", "2"])
        XCTAssertFalse(model.hasMore)
    }

    @MainActor
    func testCancelledResponseCannotPopulatePicker() async {
        let provider = PickerProvider()
        let model = HeroCollectionListModel(provider: provider, libraryID: "library")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.loadNextPage()
        }
        await task.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.error)
    }
}

private actor PickerProvider: MediaProvider {
    nonisolated let kind: ProviderKind = .plex
    nonisolated let session = UserSession(
        server: MediaServer(id: "server", name: "Server", baseURL: URL(string: "https://example.com")!, provider: .plex),
        userID: "user", userName: "Viewer", deviceID: "device", accessToken: "test-token"
    )
    private var fails = true
    func setFailure(_ value: Bool) { fails = value }

    func collections(in libraryID: String, page: PageRequest) async throws -> MediaPage {
        if fails, page.startIndex == 2 { throw AppError.serverUnreachable }
        let items = (0..<3).map { MediaItem(id: "\($0)", title: "\($0)", kind: .collection) }
        return .init(
            items: Array(items.dropFirst(page.startIndex).prefix(2)),
            startIndex: page.startIndex, totalCount: items.count
        )
    }

    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
