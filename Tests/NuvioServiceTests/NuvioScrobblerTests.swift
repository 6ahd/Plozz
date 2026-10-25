import XCTest
import CoreModels
@testable import NuvioService

/// Pins the progress rows Plozz sends to Nuvio. Nuvio's apps only match rows in
/// this exact shape: millisecond times, `<id>_s<S>e<E>` episode keys, and the
/// series id (never the episode's) for an episode.
final class NuvioScrobblerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMovieUsesItsImdbIDAndMilliseconds() throws {
        let item = MediaItem(
            id: "1", title: "Film", kind: .movie, runtime: 6000,
            providerIDs: ["Imdb": "tt0111161", "Tmdb": "278"]
        )
        let entry = try XCTUnwrap(NuvioScrobbler.entry(for: item, progress: 25, now: now))
        XCTAssertEqual(entry.contentID, "tt0111161")
        XCTAssertEqual(entry.contentType, "movie")
        XCTAssertEqual(entry.progressKey, "tt0111161")
        XCTAssertNil(entry.season)
        XCTAssertEqual(entry.duration, 6_000_000)
        XCTAssertEqual(entry.position, 1_500_000)
        XCTAssertEqual(entry.lastWatched, 1_700_000_000_000)
    }

    func testEpisodeUsesSeriesIDAndNuvioKey() throws {
        let item = MediaItem(
            id: "2", title: "Pilot", kind: .episode, parentTitle: "Show",
            seasonNumber: 1, episodeNumber: 2, runtime: 3000,
            providerIDs: ["Imdb": "tt9999999", "SeriesImdb": "tt0903747"]
        )
        let entry = try XCTUnwrap(NuvioScrobbler.entry(for: item, progress: 50, now: now))
        XCTAssertEqual(entry.contentID, "tt0903747")
        XCTAssertEqual(entry.contentType, "series")
        XCTAssertEqual(entry.videoID, "tt0903747:1:2")
        XCTAssertEqual(entry.progressKey, "tt0903747_s1e2")
        XCTAssertEqual(entry.position, 1_500_000)
    }

    func testFallsBackToTmdbAndMarksFinishedAsFullPosition() throws {
        let item = MediaItem(
            id: "3", title: "Film", kind: .movie, runtime: 100,
            providerIDs: ["tmdb": "550"]
        )
        let entry = try XCTUnwrap(NuvioScrobbler.entry(for: item, progress: 95, now: now))
        XCTAssertEqual(entry.contentID, "tmdb:550")
        XCTAssertEqual(entry.position, entry.duration)
    }

    func testSkipsMediaNuvioCannotPlace() {
        let noIDs = MediaItem(id: "4", title: "Home video", kind: .movie, runtime: 100)
        XCTAssertNil(NuvioScrobbler.entry(for: noIDs, progress: 10, now: now))
        let noRuntime = MediaItem(id: "5", title: "Film", kind: .movie, providerIDs: ["imdb": "tt1"])
        XCTAssertNil(NuvioScrobbler.entry(for: noRuntime, progress: 10, now: now))
        let episodeWithoutSeries = MediaItem(
            id: "6", title: "Ep", kind: .episode, seasonNumber: 1, episodeNumber: 1,
            runtime: 100, providerIDs: ["imdb": "tt2"]
        )
        XCTAssertNil(NuvioScrobbler.entry(for: episodeWithoutSeries, progress: 10, now: now))
    }

    func testFilmRowEncodesExplicitNullSeasonAndEpisode() throws {
        let entry = NuvioProgressEntry(
            contentID: "tt1", contentType: "movie", videoID: "tt1", season: nil, episode: nil,
            position: 1, duration: 2, lastWatched: 3, progressKey: "tt1"
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any]
        )
        XCTAssertTrue(json["season"] is NSNull)
        XCTAssertTrue(json["episode"] is NSNull)
        XCTAssertEqual(json["progress_key"] as? String, "tt1")
    }

    func testReadsNestedGoTrueSession() throws {
        let tokens = try NuvioClient.tokens(from: [
            "session": [
                "access_token": "a", "refresh_token": "r", "expires_in": 3600,
                "user": ["email": "me@example.com"]
            ] as [String: Any]
        ])
        XCTAssertEqual(tokens.accessToken, "a")
        XCTAssertEqual(tokens.refreshToken, "r")
        XCTAssertEqual(tokens.email, "me@example.com")
        XCTAssertEqual(tokens.displayName, "me@example.com")
    }
}
