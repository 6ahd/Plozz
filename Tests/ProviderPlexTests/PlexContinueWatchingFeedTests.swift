import XCTest
import CoreModels
@testable import ProviderPlex

final class PlexContinueWatchingFeedTests: XCTestCase {
    private enum Route: CaseIterable {
        case library, combinedHome, nativeHome
    }

    private let section = ServerHomeSection(
        id: "plex:continueWatching", kind: .continueWatching, includesNextUp: true
    )
    private let copies = """
    {"MediaContainer":{"size":2,"totalSize":2,"offset":0,"Metadata":[
      {"ratingKey":"101","key":"/library/metadata/101","guid":"plex://movie/shared",
       "type":"movie","librarySectionID":1,"duration":3600000,"viewOffset":600000},
      {"ratingKey":"202","key":"/library/metadata/202","guid":"plex://movie/shared",
       "type":"movie","librarySectionID":2,"duration":3600000,"viewOffset":1200000}
    ]}}
    """

    private func provider(_ stub: StubHTTPClient) -> PlexProvider {
        PlexProvider(
            session: UserSession(
                server: MediaServer(
                    id: "test", name: "Test", baseURL: URL(string: "https://plex.test")!,
                    provider: .plex
                ),
                userID: "viewer", userName: "Viewer", deviceID: "device", accessToken: "TEST_TOKEN"
            ),
            http: stub
        )
    }

    private func load(_ route: Route, using provider: PlexProvider) async throws -> [MediaItem] {
        switch route {
        case .library:
            let items = try await provider.continueWatching(limit: 20, inLibraries: ["1"])
            return items.filter { provider.contains($0, inLibrary: "1") }
        case .combinedHome:
            return try await provider.homeContinueWatching(
                limit: .max, inLibraries: nil, separateNextUp: false
            )
        case .nativeHome:
            return try await provider.serverHomeItems(
                section: section, limit: .max, excludingLibraryIDs: []
            )
        }
    }

    func testCopiesWithSharedGlobalGUIDRemainDistinctOnEverySurface() async throws {
        for route in Route.allCases {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: copies)
            let items = try await load(route, using: provider(stub))

            XCTAssertEqual(items.map(\.id), route == .library ? ["101"] : ["101", "202"])
            XCTAssertEqual(items.map(\.resumePosition), route == .library ? [600] : [600, 1200])
            XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items"])
        }
    }

    func testSharedGUIDAcrossPagesDoesNotLookLikeARepeatedPage() async throws {
        for route in [Route.combinedHome, .nativeHome] {
            let stub = StubHTTPClient()
            stub.stubSequence(pathSuffix: "/hubs/continueWatching/items", jsons: [
                """
                {"MediaContainer":{"size":1,"totalSize":2,"offset":0,"Metadata":[
                  {"ratingKey":"101","guid":"plex://movie/shared","type":"movie","librarySectionID":1}
                ]}}
                """,
                """
                {"MediaContainer":{"size":1,"totalSize":2,"offset":1,"Metadata":[
                  {"ratingKey":"202","guid":"plex://movie/shared","type":"movie","librarySectionID":2}
                ]}}
                """
            ])
            let items = try await load(route, using: provider(stub))
            XCTAssertEqual(items.map(\.id), ["101", "202"])
            XCTAssertEqual(stub.sentQueryItems.map {
                $0.first { $0.name == "X-Plex-Container-Start" }?.value
            }, ["0", "1"])
        }
    }

    func testDistinctMetadataPathsTakePrecedenceOverSharedGUIDWithoutRatingKeys() async throws {
        let payload = copies
            .replacingOccurrences(of: #""ratingKey":"101","#, with: "")
            .replacingOccurrences(of: #""ratingKey":"202","#, with: "")
        for route in [Route.combinedHome, .nativeHome] {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: payload)
            let items = try await load(route, using: provider(stub))
            XCTAssertEqual(items.count, 2)
        }
    }

    func testRepeatedLocalIdentityStillFailsRegardlessOfGlobalGUID() async throws {
        for payload in [
            copies.replacingOccurrences(of: #""ratingKey":"202""#, with: #""ratingKey":"101""#),
            copies.replacingOccurrences(of: "/library/metadata/202", with: "/library/metadata/101"),
        ] {
            for route in [Route.combinedHome, .nativeHome] {
                let stub = StubHTTPClient()
                stub.stub(pathSuffix: "/hubs/continueWatching/items", json: payload)
                stub.stub(pathSuffix: "/hubs/continueWatching", json: copies)
                do {
                    _ = try await load(route, using: provider(stub))
                    XCTFail("Repeated server-local identity must not switch feeds")
                } catch {
                    XCTAssertEqual(error as? AppError, .invalidResponse)
                }
                XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items"])
            }
        }
    }

    func testGUIDOnlyFallbackStillDetectsRepeatedItems() async throws {
        let payload = """
        {"MediaContainer":{"size":2,"totalSize":2,"offset":0,"Metadata":[
          {"guid":"plex://movie/shared","type":"movie"},
          {"guid":"plex://movie/shared","type":"movie"}
        ]}}
        """
        for route in [Route.combinedHome, .nativeHome] {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: payload)
            do {
                _ = try await load(route, using: provider(stub))
                XCTFail("GUID-only records still need repeat detection")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidResponse)
            }
            XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items"])
        }
    }

    func testInitialEndpointFailuresUseTheSamePlainHubFallbackOnEverySurface() async throws {
        for status in [404, 500, 200] {
            for route in Route.allCases {
                let stub = StubHTTPClient()
                stub.stub(pathSuffix: "/hubs/continueWatching/items", json: "{}", status: status)
                stub.stub(pathSuffix: "/hubs/continueWatching", json: copies)
                let items = try await load(route, using: provider(stub))
                XCTAssertEqual(items.map(\.id), route == .library ? ["101"] : ["101", "202"])
                XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items", "/hubs/continueWatching"])
            }
        }
    }

    func testUnavailableHubsUseLegacyFeedOnEverySurface() async throws {
        for route in Route.allCases {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: "{}", status: 404)
            stub.stub(pathSuffix: "/hubs/continueWatching", json: "{}", status: 500)
            stub.stub(pathSuffix: "/library/onDeck", json: copies)
            let items = try await load(route, using: provider(stub))
            XCTAssertEqual(items.map(\.id), route == .library ? ["101"] : ["101", "202"])
            XCTAssertEqual(stub.sentPaths, [
                "/hubs/continueWatching/items", "/hubs/continueWatching", "/library/onDeck"
            ])
        }
    }

    func testEmptyHubIsAuthoritativeOnEverySurface() async throws {
        for route in Route.allCases {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: """
            {"MediaContainer":{"size":0,"totalSize":0,"offset":0,"Metadata":[]}}
            """)
            stub.stub(pathSuffix: "/hubs/continueWatching", json: copies)
            stub.stub(pathSuffix: "/library/onDeck", json: copies)
            let items = try await load(route, using: provider(stub))
            XCTAssertTrue(items.isEmpty)
            XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items"])
        }
    }

    func testProtectedFailuresDoNotTryAnotherEndpointOnAnySurface() async throws {
        let failures: [AppError] = [
            .unauthorized, .invalidCredentials, .accessRestricted, .rateLimited(retryAfter: 30),
            .cancelled, .serverUnreachable, .conflict, .unknown("test failure"),
        ]
        for failure in failures {
            for route in Route.allCases {
                let stub = StubHTTPClient()
                stub.error = failure
                do {
                    _ = try await load(route, using: provider(stub))
                    XCTFail("Protected failure must propagate")
                } catch {
                    XCTAssertEqual(error as? AppError, failure)
                }
                XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items"])
            }
        }
    }

    func testPlainHubAuthenticationFailureStopsBeforeLegacyFeed() async throws {
        for route in Route.allCases {
            let stub = StubHTTPClient()
            stub.stub(pathSuffix: "/hubs/continueWatching/items", json: "{}", status: 404)
            stub.stub(pathSuffix: "/hubs/continueWatching", json: "{}", status: 401)
            stub.stub(pathSuffix: "/library/onDeck", json: copies)
            do {
                _ = try await load(route, using: provider(stub))
                XCTFail("Authentication failure must not fall through to legacy data")
            } catch {
                XCTAssertEqual(error as? AppError, .unauthorized)
            }
            XCTAssertEqual(stub.sentPaths, ["/hubs/continueWatching/items", "/hubs/continueWatching"])
        }
    }

    func testFailureAfterFirstPageDoesNotFallBackOrPublishPartialHomeFeed() async throws {
        for route in [Route.combinedHome, .nativeHome] {
            let stub = StubHTTPClient()
            stub.stubSequence(pathSuffix: "/hubs/continueWatching/items", responses: [
                (json: """
                 {"MediaContainer":{"size":1,"totalSize":2,"offset":0,"Metadata":[
                   {"ratingKey":"101","type":"movie","librarySectionID":1}
                 ]}}
                 """, status: 200),
                (json: "{}", status: 500),
            ])
            stub.stub(pathSuffix: "/hubs/continueWatching", json: copies)
            stub.stub(pathSuffix: "/library/onDeck", json: copies)
            do {
                _ = try await load(route, using: provider(stub))
                XCTFail("An incomplete authoritative feed must remain a failure")
            } catch {
                XCTAssertEqual(error as? AppError, .invalidResponse)
            }
            XCTAssertEqual(stub.sentPaths, Array(repeating: "/hubs/continueWatching/items", count: 2))
        }
    }

    func testNativeFallbackPreservesHiddenLibraryFilteringAndBatchedErrorTypes() async throws {
        let stub = StubHTTPClient()
        stub.stub(pathSuffix: "/hubs/continueWatching/items", json: "{}", status: 500)
        stub.stub(pathSuffix: "/hubs/continueWatching", json: copies)
        let provider = provider(stub)
        let results = await provider.serverHomeItems(
            sections: [section], limit: 1, excludingLibraryIDs: ["1"]
        )
        let items = try XCTUnwrap(results[section.id]).get()
        XCTAssertEqual(items.map(\.id), ["202"])
        XCTAssertEqual(items.first?.resumePosition, 1200)
        XCTAssertTrue(stub.sentQueryItems.allSatisfy {
            $0.contains(.init(name: "X-Plex-Container-Size", value: "100"))
        })

        stub.error = .rateLimited(retryAfter: 30)
        let failures = await provider.serverHomeItems(
            sections: [section], limit: .max, excludingLibraryIDs: []
        )
        switch try XCTUnwrap(failures[section.id]) {
        case .failure(let error): XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        case .success: XCTFail("Native Home must retain the typed failure")
        }
    }
}
