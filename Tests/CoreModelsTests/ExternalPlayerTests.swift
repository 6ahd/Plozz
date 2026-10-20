import XCTest
@testable import CoreModels

final class ExternalPlayerTests: XCTestCase {
    private let media = URL(string: "https://server.test/media/a%20b.mkv?token=synthetic%2Bvalue&x=1#part")!
    private let nonce = UUID()

    func testCallbackPlayersCarryNestedURLsResumeSubtitlesAndUniqueReturnScheme() throws {
        for player in [ExternalPlayer.nativePlayer, .infuse] {
            let subtitles = (0..<10).map { URL(string: "https://server.test/\($0).srt?token=test&lang=en")! }
            let url = try ExternalPlayerURL.make(
                settings: .init(player: player), mediaURL: media, title: "A & B + C.mkv",
                position: 123.9, subtitles: subtitles, callbackScheme: "com.test.external-player", nonce: nonce
            )
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(url.scheme, player.scheme)
            XCTAssertEqual(url.path, "/play")
            XCTAssertFalse(url.absoluteString.contains("+"))
            XCTAssertEqual(query.first { $0.name == "url" }?.value, media.absoluteString)
            XCTAssertEqual(query.first { $0.name == "filename" }?.value, "A & B + C.mkv")
            XCTAssertEqual(query.first { $0.name == "position" }?.value, "123")
            XCTAssertEqual(query.filter { $0.name == "sub" }.compactMap(\.value), subtitles.prefix(8).map(\.absoluteString))
            for outcome in ["success", "error"] {
                let callback = try XCTUnwrap(query.first { $0.name == "x-" + outcome }?.value)
                let parsed = try XCTUnwrap(URLComponents(string: callback))
                XCTAssertEqual(parsed.scheme, "com.test.external-player")
                XCTAssertEqual(parsed.path, "/" + outcome)
                XCTAssertEqual(parsed.queryItems, [.init(name: "session", value: nonce.uuidString)])
            }
        }
    }

    func testVLCUsesDocumentedStreamActionWithoutPretendingToSupportResumeOrProgress() throws {
        let url = try ExternalPlayerURL.make(
            settings: .init(player: .vlc), mediaURL: media, title: "Movie",
            position: 123, subtitles: [media, media], callbackScheme: "test", nonce: nonce
        )
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.scheme, "vlc-x-callback")
        XCTAssertEqual(url.path, "/stream")
        XCTAssertEqual(query.filter { $0.name == "sub" }.count, 1)
        XCTAssertFalse(query.contains { ["position", "x-success", "x-error"].contains($0.name) })
    }

    func testCustomTemplateEncodesTheEntireMediaURLAsOneValue() throws {
        let url = try ExternalPlayerURL.make(
            settings: .init(player: .custom, customURLTemplate: "testplayer://play?video={url}&mode=1"),
            mediaURL: media, title: "Ignored", position: 0, callbackScheme: "test", nonce: nonce
        )
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query, [.init(name: "video", value: media.absoluteString), .init(name: "mode", value: "1")])
    }

    func testInvalidCustomTemplatesFailClosed() {
        for template in [
            "", "testplayer://play", "testplayer://{url}/{url}", "testplayer://{url}/{title}",
            "https://example.test?url={url}", "file:///{url}", "javascript:{url}",
            "plozz://play?url={url}", "plozz-dev://play?url={url}",
            "com.test.external-player://external-player?url={url}",
            "testplayer://user:password@play/{url}", "testplayer://play?url={url} "
        ] {
            XCTAssertThrowsError(try ExternalPlayerURL.validateCustomTemplate(template), template)
        }
    }

    func testAppLocalCredentialAuthorityAndUnsupportedMediaURLsAreRejected() {
        for value in [
            "http://localhost/video", "http://127.0.0.2/video", "http://[::1]/video",
            "http://[::ffff:127.0.0.1]/video", "http://proxy.localhost/video",
            "file:///video.mkv", "smb://server/video", "https://user:pass@server.test/video",
            "https://server.test/video.mpd"
        ] {
            XCTAssertFalse(ExternalPlayerURL.isSupportedMediaURL(URL(string: value)!), value)
        }
        XCTAssertTrue(ExternalPlayerURL.isSupportedMediaURL(URL(string: "http://192.168.1.2/video")!))
    }

    func testInvalidResumePositionsAreRejected() {
        for position in [Double.nan, .infinity, -1, Double(Int.max)] {
            XCTAssertThrowsError(try ExternalPlayerURL.make(
                settings: .init(player: .infuse), mediaURL: media, title: "Movie",
                position: position, callbackScheme: "test", nonce: nonce
            ))
        }
    }

    func testOldAndFutureSettingsPreserveOtherPreferencesAndDefaultToPlozz() throws {
        for external in ["", #","externalPlayer":{"player":"futurePlayer","customURLTemplate":""}"#] {
            let data = Data(#"{"autoPlayNextEpisode":false\#(external)}"#.utf8)
            let settings = try JSONDecoder().decode(PlaybackSettings.self, from: data)
            XCTAssertEqual(settings.externalPlayer.player, .builtIn)
            XCTAssertFalse(settings.autoPlayNextEpisode)
        }
    }

    func testExternalSelectionRoundTripsAndTransfersOnlyWithItsProfile() throws {
        let suite = "ExternalPlayerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = PlaybackSettings.default
        settings.externalPlayer = .init(player: .custom, customURLTemplate: "testplayer://play?url={url}")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSettings.self, from: data).externalPlayer, settings.externalPlayer)
        defaults.set(data, forKey: SettingsKey.scoped("com.plozz.playbackSettings", namespace: "one"))
        let captured = ProfileSettingsTransfer.capture(namespace: "one", defaults: defaults)
        ProfileSettingsTransfer.apply(captured, namespace: "two", defaults: defaults)
        let restored = try XCTUnwrap(defaults.data(forKey: SettingsKey.scoped("com.plozz.playbackSettings", namespace: "two")))
        XCTAssertEqual(try JSONDecoder().decode(PlaybackSettings.self, from: restored).externalPlayer, settings.externalPlayer)
        XCTAssertNil(defaults.data(forKey: "com.plozz.playbackSettings"))
    }
}
