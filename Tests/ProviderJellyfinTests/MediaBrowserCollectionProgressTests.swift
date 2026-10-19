import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderJellyfin

final class MediaBrowserCollectionProgressTests: XCTestCase {
    func testBothProvidersPublishOnlyAResolvedPrefixBeforeTheScanFinishes() async throws {
        for kind: ProviderKind in [.jellyfin, .emby] {
            let http = CollectionProgressHTTP(blocked: ["c0", "c7"])
            let provider = provider(http, kind: kind)
            let updates = CollectionProgressUpdates()
            let task = Task {
                try await provider.collections(in: "library", page: PageRequest()) { await updates.append($0) }
            }
            let reachedTail = await wait { await http.requested.contains("c7") }
            XCTAssertTrue(reachedTail)
            let before = await updates.values
            XCTAssertTrue(before.allSatisfy { $0.items.isEmpty }, "A later result cannot jump ahead of an unresolved candidate.")
            await http.release("c0")
            let painted = await wait { await updates.values.last?.items.count == 4 }
            XCTAssertTrue(painted, "Usable cards must arrive while the final membership request is still held.")
            let early = await updates.values.last
            XCTAssertEqual(early?.items.map(\.id), ["c0", "c1", "c2", "c3"])
            XCTAssertTrue(early?.items.allSatisfy { $0.libraryID == "library" } == true)
            await http.release("c7")
            let result = try await task.value
            XCTAssertEqual(result.items.map(\.id), ["c0", "c1", "c2", "c3"])
            let all = await updates.values
            XCTAssertEqual(all.last?.checked, 8)
            for update in all {
                XCTAssertEqual(update.items.map(\.id), Array(result.items.prefix(update.items.count)).map(\.id))
            }
            let count = await http.count
            let next = try await provider.collections(in: "library", page: PageRequest(startIndex: 2, limit: 2))
            XCTAssertEqual(next.items.map(\.id), ["c2", "c3"])
            let after = await http.count
            XCTAssertEqual(after, count)
        }
    }

    func testRandomProgressIsAPrefixOfTheFinalCachedShuffle() async throws {
        let http = CollectionProgressHTTP()
        let provider = provider(http)
        let updates = CollectionProgressUpdates()
        let sort = CoreModels.SortDescriptor(field: .random, direction: .ascending)
        let result = try await provider.collections(in: "library", page: PageRequest(sort: sort)) {
            await updates.append($0)
        }
        let all = await updates.values
        for update in all {
            XCTAssertEqual(update.items.map(\.id), Array(result.items.prefix(update.items.count)).map(\.id))
        }
        XCTAssertEqual(Set(result.items.map(\.id)), Set(["c0", "c1", "c2", "c3"]))
        let next = try await provider.collections(in: "library", page: PageRequest(startIndex: 1, limit: 3, sort: sort))
        XCTAssertEqual(next.items.map(\.id), Array(result.items.dropFirst()).map(\.id))
    }

    func testOnlyOneConnectionRetryAndNoRetriesForCancellationOrInvalidData() async throws {
        for error: AppError in [.serverUnreachable, .cancelled, .invalidResponse] {
            let http = CollectionProgressHTTP(failure: error, failureCount: 2)
            do {
                _ = try await provider(http).collections(in: "library", page: PageRequest())
                XCTFail("A permanent failure must not become a partial successful snapshot.")
            } catch let actual as AppError {
                XCTAssertEqual(actual, error)
            }
            let count = await http.count
            XCTAssertEqual(count, error == .serverUnreachable ? 2 : 1)
        }
        let transient = CollectionProgressHTTP(failure: .serverUnreachable, failureCount: 1)
        let result = try await provider(transient).collections(in: "library", page: PageRequest())
        XCTAssertEqual(result.totalCount, 4)
        let count = await transient.count
        XCTAssertEqual(count, 11, "One failed candidate read, its retry, one library read, and eight member reads.")
    }

    private func provider(_ http: CollectionProgressHTTP, kind: ProviderKind = .jellyfin) -> JellyfinProvider {
        JellyfinProvider(session: UserSession(
            server: MediaServer(id: "fixture", name: "Fixture", baseURL: URL(string: "https://fixture.invalid")!, provider: kind),
            userID: "user", userName: "User", deviceID: "device", accessToken: "fixture"
        ), http: http)
    }

    private func wait(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private actor CollectionProgressUpdates {
    private(set) var values: [LibraryCollectionProgress] = []
    func append(_ value: LibraryCollectionProgress) { values.append(value) }
}

private actor CollectionProgressHTTP: HTTPClient {
    private var blocked: Set<String>
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private let failure: AppError
    private var failureCount: Int
    private(set) var requested = Set<String>()
    private(set) var count = 0

    init(blocked: Set<String> = [], failure: AppError = .serverUnreachable, failureCount: Int = 0) {
        self.blocked = blocked
        self.failure = failure
        self.failureCount = failureCount
    }

    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if failureCount > 0 {
            failureCount -= 1
            throw failure
        }
        let query = Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value ?? "") })
        let parent = query["ParentId"] ?? ""
        requested.insert(parent)
        if blocked.contains(parent) {
            await withCheckedContinuation { waiters[parent] = $0 }
        }
        try Task.checkCancellation()
        let items: [[String: String]]
        if query["IncludeItemTypes"] == "BoxSet" {
            items = (0..<8).map { ["Id": "c\($0)", "Name": "Collection \($0)", "Type": "BoxSet"] }
        } else if parent == "library" || ["c0", "c1", "c2", "c3"].contains(parent) {
            items = [["Id": "movie", "Type": "Movie"]]
        } else { items = [] }
        let data = try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": items.count])
        return (data, HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func release(_ parent: String) {
        blocked.remove(parent)
        waiters.removeValue(forKey: parent)?.resume()
    }
}
