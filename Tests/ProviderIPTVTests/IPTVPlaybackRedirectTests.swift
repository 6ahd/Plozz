import CoreModels
import CoreNetworking
import Foundation
@testable import ProviderIPTV
import XCTest

final class IPTVPlaybackRedirectTests: XCTestCase {
    func testPlaybackRedirectsPreserveProviderURLsButNeverCrossOriginAccountHeaders() throws {
        let source = try XCTUnwrap(URL(string: "https://provider.example/live/viewer/fixture-password/10.m3u8"))
        var original = URLRequest(url: source)
        original.setValue("Bearer fixture-token", forHTTPHeaderField: "Authorization")
        original.setValue("session=fixture-cookie", forHTTPHeaderField: "Cookie")
        original.setValue("private-header", forHTTPHeaderField: "X-Provider-Key")
        var previous = source
        for destination in [
            "http://delivery.example:8080/live/viewer/fixture-password/10.m3u8",
            "https://other-delivery.example/video?password=fixture-password&token=fixture-token",
            "https://provider.example/return/fixture-password"
        ] {
            var redirect = original
            redirect.url = try XCTUnwrap(URL(string: destination))
            redirect.setValue("bytes=10-", forHTTPHeaderField: "Range")
            redirect.setValue("etag", forHTTPHeaderField: "If-Range")
            let allowed = try XCTUnwrap(IPTVRedirectPolicy.request(
                redirect, previous: previous, original: original,
                sensitiveValues: ["fixture-password"], scope: .playback
            ))
            XCTAssertEqual(allowed.url, redirect.url)
            for name in ["Authorization", "Cookie", "X-Provider-Key"] {
                XCTAssertNil(allowed.value(forHTTPHeaderField: name))
            }
            XCTAssertEqual(allowed.value(forHTTPHeaderField: "Range"), "bytes=10-")
            XCTAssertEqual(allowed.value(forHTTPHeaderField: "If-Range"), "etag")
            previous = try XCTUnwrap(allowed.url)
        }
        for destination in ["file:///tmp/video", "ftp://delivery.example/video", "https://viewer:fixture@delivery.example/video"] {
            let url = try XCTUnwrap(URL(string: destination))
            XCTAssertNil(IPTVRedirectPolicy.request(
                URLRequest(url: url),
                previous: source, original: original, scope: .playback
            ))
        }
        var sameOrigin = original
        sameOrigin.url = URL(string: "https://provider.example/live/viewer/fixture-password/next.m3u8")
        XCTAssertEqual(IPTVRedirectPolicy.request(
            sameOrigin, previous: source, original: original, scope: .playback
        )?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    }

    func testXtreamAndPlaylistAccountsFollowChangingDeliveryServersForHLSAndFiles() async throws {
        for mode in [IPTVCredential.Mode.xtream, .playlist] {
            for format in ["m3u8", "ts", "mp4", "mkv"] {
                try await checkPlayback(mode: mode, format: format)
            }
        }
    }

    private func checkPlayback(mode: IPTVCredential.Mode, format: String) async throws {
        let group = format == "mkv" ? "series" : format == "mp4" ? "movie" : "live"
        let path = "\(group)/viewer/fixture-password/10.\(format)"
        let media = Data("fixture-media".utf8)
        let segmentServer = try IPTVTestHTTPServer { request in
            for name in ["authorization:", "cookie:", "x-provider-key:"] {
                XCTAssertFalse(request.lowercased().contains(name))
            }
            XCTAssertTrue(request.hasPrefix("GET /fixture-password/media "))
            return .init(data: media, headers: ["Content-Type": "video/mp2t"])
        }
        let segmentURL = try await segmentServer.start()
        addTeardownBlock { await segmentServer.stop() }
        let delivery = try IPTVTestHTTPServer { request in
            for name in ["authorization:", "cookie:", "x-provider-key:"] {
                XCTAssertFalse(request.lowercased().contains(name))
            }
            if format == "m3u8", request.hasPrefix("GET /\(path) ") {
                return .init(data: Data("""
                #EXTM3U
                #EXT-X-TARGETDURATION:6
                #EXT-X-KEY:METHOD=AES-128,URI="key"
                #EXTINF:6,
                segment.ts
                #EXT-X-ENDLIST
                """.utf8), headers: ["Content-Type": "application/vnd.apple.mpegurl"])
            }
            if format == "m3u8" {
                XCTAssertTrue(request.hasPrefix("GET /live/viewer/fixture-password/segment.ts ")
                    || request.hasPrefix("GET /live/viewer/fixture-password/key "))
                return .init(status: 302, headers: [
                    "Location": segmentURL.appendingPathComponent("fixture-password/media").absoluteString
                ])
            } else {
                XCTAssertTrue(request.hasPrefix("GET /\(path) ") || request.hasPrefix("HEAD /\(path) "))
                XCTAssertTrue(request.lowercased().contains("range: bytes=10-22"))
            }
            return .init(data: media, headers: ["Content-Type": format == "mp4" ? "video/mp4" : "video/mp2t"])
        }
        let deliveryURL = try await delivery.start()
        addTeardownBlock { await delivery.stop() }
        let relay = try IPTVTestHTTPServer { _ in
            .init(status: 307, headers: ["Location": deliveryURL.appendingPathComponent(path).absoluteString])
        }
        let relayURL = try await relay.start()
        addTeardownBlock { await relay.stop() }
        let source = try IPTVTestHTTPServer { request in
            if request.hasPrefix("GET /\(group)/") || request.hasPrefix("HEAD /\(group)/") {
                return .init(status: 302, headers: ["Location": relayURL.appendingPathComponent(path).absoluteString])
            }
            if request.hasPrefix("GET /get.php") {
                let name = format == "mkv" ? "Series S01E01" : "Fixture"
                return .init(data: Data("#EXTM3U\n#EXTINF:\(format == "mp4" ? "60" : "-1"),\(name)\n\(path)\n".utf8))
            }
            let body: String
            if request.contains("action=get_live_streams") {
                body = #"[{"stream_id":10,"name":"News","category_id":"1"}]"#
            } else if request.contains("action=get_vod_streams") {
                body = #"[{"stream_id":10,"name":"Film","container_extension":"mp4"}]"#
            } else if request.contains("action=get_vod_info") {
                body = #"{"info":{},"movie_data":{"container_extension":"mp4"}}"#
            } else if request.contains("action=get_series_info") {
                body = #"{"info":{},"episodes":{"1":[{"id":"10","episode_num":1,"title":"Pilot","container_extension":"mkv"}]}}"#
            } else if request.contains("action=get_series ") {
                body = #"[{"series_id":30,"name":"Series"}]"#
            } else if request.contains("action=") { body = "[]" }
            else {
                body = #"{"user_info":{"auth":1,"status":"Active","allowed_output_formats":["\#(format)"]}}"#
            }
            return .init(data: Data(body.utf8), headers: ["Content-Type": "application/json"])
        }
        let sourceURL = try await source.start()
        addTeardownBlock { await source.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let address = mode == .xtream ? sourceURL
            : try XCTUnwrap(URL(string: "get.php?username=viewer&password=fixture-password", relativeTo: sourceURL)?.absoluteURL)
        let credential = try IPTVCredential(
            mode: mode, address: address,
            username: mode == .xtream ? "viewer" : "", password: mode == .xtream ? "fixture-password" : "",
            headers: ["Authorization": "Bearer fixture-token", "Cookie": "session=fixture-cookie",
                      "X-Provider-Key": "private-header"]
        )
        let login = try await IPTVProvider.signIn(
            credential: credential, name: "Fixture", deviceID: "fixture", cacheDirectory: root
        )
        let provider = try IPTVProvider(
            context: .init(
                session: login, accountID: "account", credentialRevision: .init(),
                localMediaContext: .init(accountID: "account", profileID: "viewer", profileNamespace: nil)
            ), cacheDirectory: root
        )
        addTeardownBlock { await provider.teardown() }
        let itemID: String
        if format == "mkv" {
            let series = try await provider.items(in: "series", kind: .series, page: .init(limit: 1))
            let seasons = try await provider.children(of: XCTUnwrap(series.items.first?.id))
            let episodes = try await provider.children(of: XCTUnwrap(seasons.first?.id))
            itemID = try XCTUnwrap(episodes.first?.id)
        } else if format == "mp4" {
            let items = try await provider.items(in: "movies", kind: .movie, page: .init(limit: 1))
            itemID = try XCTUnwrap(items.items.first?.id)
        } else {
            let channels = try await provider.liveTVChannels()
            itemID = try XCTUnwrap(channels.first?.id)
        }
        let request = try await provider.playbackInfo(for: itemID)
        guard case .authenticatedHTTP(let locator) = request.playbackSource else {
            return XCTFail("Playback must remain behind the authenticated proxy.")
        }
        let url = try await provider.resolveHTTPResource(locator)
        XCTAssertFalse(url.absoluteString.contains("fixture-password"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var download = URLRequest(url: url)
        if format != "m3u8" { download.setValue("bytes=10-22", forHTTPHeaderField: "Range") }
        let (data, response) = try await session.data(for: download)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        if format == "m3u8" {
            let manifest = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(manifest.contains("fixture-password"))
            XCTAssertFalse(manifest.contains(deliveryURL.absoluteString))
            let segment = try XCTUnwrap(manifest.split(separator: "\n").first { !$0.hasPrefix("#") })
            let key = try XCTUnwrap(manifest.split(separator: "\"").dropFirst().first)
            for resource in [segment, key] {
                let resourceURL = try XCTUnwrap(URL(string: String(resource)))
                XCTAssertEqual(resourceURL.host, "127.0.0.1")
                let (bytes, response) = try await session.data(from: resourceURL)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(bytes, media)
            }
        } else {
            XCTAssertEqual(data, media)
            download.httpMethod = "HEAD"
            let (head, response) = try await session.data(for: download)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertTrue(head.isEmpty)
        }
        await provider.teardown()
        await source.stop()
        await relay.stop()
        await delivery.stop()
        await segmentServer.stop()
    }

    func testPlaybackPermissionDoesNotAuthorizeLoginCatalogOrGuideRedirects() async throws {
        let delivery = try IPTVTestHTTPServer { _ in
            XCTFail("Account requests must not forward credentials to delivery servers.")
            return .init(status: 500)
        }
        let deliveryURL = try await delivery.start()
        addTeardownBlock { await delivery.stop() }
        let source = try IPTVTestHTTPServer { _ in
            .init(status: 302, headers: ["Location": deliveryURL.appendingPathComponent("fixture-password/data").absoluteString])
        }
        let sourceURL = try await source.start()
        addTeardownBlock { await source.stop() }
        let credential = try IPTVCredential(
            mode: .xtream, address: sourceURL, username: "viewer", password: "fixture-password"
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let client = try IPTVClient(credential: credential, directory: root)
        addTeardownBlock { await client.cancel() }
        do {
            try await client.authenticate()
            XCTFail("Login redirects must remain protected.")
        } catch { XCTAssertEqual(error as? LiveTVSourceImportError, .redirectBlocked) }
        do {
            _ = try await client.guideData(from: sourceURL.appendingPathComponent("xmltv.php"))
            XCTFail("Guide redirects must remain protected.")
        } catch { XCTAssertEqual(error as? LiveTVSourceImportError, .redirectBlocked) }
        let http = IPTVHTTP(sensitiveValues: ["fixture-password"])
        defer { http.cancel() }
        do {
            _ = try await http.bytes(url: sourceURL.appendingPathComponent("catalog"), headers: [:])
            XCTFail("Catalogue HTTP requests must remain protected by default.")
        } catch { XCTAssertEqual(error as? LiveTVSourceImportError, .redirectBlocked) }
        let received = await delivery.requestCount
        XCTAssertEqual(received, 0)
    }
}
