import CoreModels
import CoreNetworking
import Foundation
import Observation

@MainActor
@Observable
final class HeroCollectionListModel {
    public private(set) var items: [MediaItem] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = true
    public private(set) var error: AppError?
    private let provider: any MediaProvider
    private let libraryID: String
    private var nextIndex = 0

    public init(provider: any MediaProvider, libraryID: String) {
        self.provider = provider
        self.libraryID = libraryID
    }

    public func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await provider.collections(
                in: libraryID, page: PageRequest(startIndex: nextIndex, limit: 50)
            )
            try Task.checkCancellation()
            var seen = Set(items.map(\.id))
            guard page.startIndex == nextIndex, page.totalCount >= 0,
                  page.items.allSatisfy({
                      $0.kind == .collection && !$0.id.isEmpty && seen.insert($0.id).inserted
                  }),
                  !page.items.isEmpty || nextIndex >= page.totalCount else {
                throw AppError.invalidResponse
            }
            items += page.items
            nextIndex = page.endIndex
            hasMore = page.hasMore
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, (error as? AppError) != .cancelled else { return }
            self.error = (error as? AppError) ?? .unknown("")
            PlozzLog.app.error("Hero collection picker could not load a page")
        }
    }
}
