import CoreModels
import FeaturePlayback
import XCTest
@testable import EnginePlozzigen

@MainActor
final class EmbeddedChapterTests: XCTestCase {
    func testNativeReadsMP4ChaptersFromThePlayingAsset() async throws {
        try await verifyChapters(engine: NativeVideoEngine(), extension: "mp4")
    }

    func testPlozzigenReadsMP4ChaptersDuringItsExistingLoad() async throws {
        try await verifyChapters(engine: PlozzigenVideoEngine(), extension: "mp4")
    }

    func testPlozzigenReadsMatroskaChaptersDuringItsExistingLoad() async throws {
        try await verifyChapters(engine: PlozzigenVideoEngine(), extension: "mkv")
    }

    private func verifyChapters(engine: any VideoEngine, extension fileExtension: String) async throws {
        defer { engine.stop() }
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "chapters", withExtension: fileExtension, subdirectory: "Fixtures"
        ))
        var publications = 0
        engine.onChaptersChanged = { publications += 1 }
        let item = MediaItem(id: "chapter-fixture", title: "Synthetic chapter fixture", kind: .movie)
        await engine.load(request: PlaybackRequest(item: item, streamURL: url), startPosition: 0)
        try await waitUntil { !engine.chapters.isEmpty && engine.isPlaybackPositionReady }
        XCTAssertEqual(engine.chapters.map(\.start), [0, 2, 4])
        XCTAssertEqual(engine.chapters.map(\.title), ["Opening", "The journey", "Finale"])
        XCTAssertGreaterThan(publications, 0)
        engine.pause()
        await engine.seek(to: 2)
        XCTAssertEqual(engine.currentTime, 2, accuracy: 0.25)
        XCTAssertTrue(engine.isPaused)
        engine.stop()
        XCTAssertTrue(engine.chapters.isEmpty)

        let plain = try XCTUnwrap(Bundle.module.url(
            forResource: "no-chapters", withExtension: "mp4", subdirectory: "Fixtures"
        ))
        let previousPublications = publications
        await engine.load(request: PlaybackRequest(item: item, streamURL: plain), startPosition: 0)
        try await waitUntil { engine.isPlaybackPositionReady && publications > previousPublications }
        XCTAssertTrue(engine.chapters.isEmpty, "A new source must never retain the previous file's chapters.")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "Embedded chapter playback did not become ready.")
    }
}
