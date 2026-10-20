import CoreModels
import XCTest
@testable import AppRuntime

@MainActor
final class ExternalPlaybackRuntimeTests: XCTestCase {
    func testDefaultAndNonVideoPlaybackDoNotOpenAnotherApp() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        fixture.settings.externalPlayer.player = .builtIn
        let builtIn = try await fixture.launch()
        XCTAssertFalse(builtIn)
        fixture.settings.externalPlayer.player = .infuse
        fixture.item.kind = .video
        let live = try await fixture.launch()
        XCTAssertFalse(live)
        XCTAssertTrue(fixture.opened.isEmpty)
    }

    func testLaunchPreservesVersionResumeAndPersistsOnlyNonSecretReceipt() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        let opened = try await fixture.launch()
        XCTAssertTrue(opened)
        XCTAssertEqual(fixture.selectedVersion, "version-one")
        let query = try XCTUnwrap(URLComponents(url: fixture.opened[0], resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "position" }?.value, "115")
        let data = try XCTUnwrap(fixture.defaults.data(forKey: "com.plozz.externalPlaybackReceipt"))
        let persisted = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(persisted.contains("synthetic-token"))
        XCTAssertFalse(persisted.contains("https://"))
        XCTAssertFalse(persisted.contains("Fixture movie"))
        XCTAssertNil(fixture.runtime.returnID)
    }

    func testUnavailableAndOpenFailureNeverLeaveAReceipt() async {
        for installed in [false, true] {
            let fixture = ExternalPlaybackFixture()
            defer { fixture.cleanup() }
            fixture.installed = installed
            fixture.openSucceeds = false
            do {
                _ = try await fixture.launch()
                XCTFail("Expected an unavailable-player failure")
            } catch { XCTAssertEqual(error as? ExternalPlayerError, .unavailable) }
            XCTAssertNil(fixture.runtime.receipt)
        }
    }

    func testSourceRestrictionsAndRejectedStreamingSessionCleanup() async {
        for mode in 0..<5 {
            let fixture = ExternalPlaybackFixture()
            defer { fixture.cleanup() }
            switch mode {
            case 0: fixture.request.streamURL = URL(fileURLWithPath: "/video.mkv")
            case 1: fixture.request.streamURL = URL(string: "http://127.0.0.1/video")
            case 2: fixture.request.externalAudioURL = fixture.media
            case 3: fixture.request.isTranscoding = true
            default:
                fixture.request.streamingSessionID = "converted-session"
                fixture.request.deliveryMode = .transcode
            }
            do {
                _ = try await fixture.launch()
                XCTFail("Expected source rejection")
            } catch { XCTAssertEqual(error as? ExternalPlayerError, .unsupportedSource) }
            XCTAssertTrue(fixture.opened.isEmpty)
            XCTAssertEqual(fixture.releasedSessions, mode == 4 ? 1 : 0)
        }
    }

    func testProfileChangeDuringPreparationPreventsLaunch() async {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        fixture.beforeRequest = { fixture.profileID = "another-profile" }
        do {
            _ = try await fixture.launch()
            XCTFail("Expected canceled handoff")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertNil(fixture.runtime.receipt)
    }

    func testMobileConversionPolicyIsNotBypassed() async {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        for options in [
            StreamingPlaybackOptions(quality: .hd720),
            StreamingPlaybackOptions(quality: .original, forceTranscoding: true)
        ] {
            do {
                _ = try await fixture.runtime.launch(
                    item: fixture.item, startPosition: 0, settings: fixture.settings,
                    streamingOptions: options, context: { fixture.context }, isPresented: { true }
                )
                XCTFail("Constrained playback must stay internal")
            } catch { XCTAssertEqual(error as? ExternalPlayerError, .unsupportedSource) }
        }
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertNil(fixture.selectedVersion)
    }

    func testDownloadedVideoDoesNotLeakAnAppPrivateFile() async {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        fixture.offlineResolver = ExternalOfflineResolver()
        do {
            _ = try await fixture.launch()
            XCTFail("Downloaded files must stay internal")
        } catch { XCTAssertEqual(error as? ExternalPlayerError, .unsupportedSource) }
        XCTAssertTrue(fixture.opened.isEmpty)
        XCTAssertNil(fixture.selectedVersion)
    }

    func testCallbackSchemeAndNonceAreCaseInsensitive() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        var callback = try XCTUnwrap(URLComponents(url: fixture.callback(position: "300"), resolvingAgainstBaseURL: false))
        callback.scheme = fixture.callbackScheme.uppercased()
        callback.queryItems = callback.queryItems?.map {
            $0.name == "session" ? .init(name: $0.name, value: $0.value?.lowercased()) : $0
        }
        XCTAssertTrue(fixture.runtime.receive(try XCTUnwrap(callback.url)))
        XCTAssertEqual(fixture.runtime.receipt?.position, 300)
    }

    func testChangedIdentityDuringReturnHydrationDoesNotPublishProgress() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        fixture.runtime.receive(try fixture.callback(position: "300"))
        fixture.beforeItem = { fixture.userID = "different-viewer" }
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in XCTFail("Changed viewer") }
        XCTAssertNotNil(fixture.runtime.returnID)
        fixture.userID = "user"
        fixture.beforeItem = nil
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in }
        XCTAssertNil(fixture.runtime.receipt)
    }

    func testReturnedProgressSurvivesRelaunchAndWaitsForAuthorizedOwner() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        let receiptID = try XCTUnwrap(fixture.runtime.receipt?.id)
        fixture.runtime.receive(try fixture.callback(position: "300"))
        let restored = ExternalPlaybackRuntime(
            defaults: fixture.defaults, callbackScheme: fixture.callbackScheme,
            canOpen: { _ in false }, open: { _ in false }
        )
        fixture.profileID = "other"
        await restored.processReturn(context: { fixture.context }) { _ in XCTFail("Wrong profile") }
        fixture.profileID = "profile"
        fixture.authorized = false
        await restored.processReturn(context: { fixture.context }) { _ in XCTFail("Locked profile") }
        fixture.authorized = true
        fixture.userID = "other-user"
        await restored.processReturn(context: { fixture.context }) { _ in XCTFail("Wrong server user") }
        fixture.userID = "user"
        let revision = fixture.account.credentialRevision
        fixture.account.credentialRevision = CredentialRevision()
        await restored.processReturn(context: { fixture.context }) { _ in XCTFail("Rotated credentials") }
        fixture.account.credentialRevision = revision
        var result: ExternalPlaybackCompletion?
        await restored.processReturn(context: { fixture.context }) { result = $0 }
        XCTAssertEqual(result?.id, receiptID)
        XCTAssertEqual(result?.position, 300)
        XCTAssertEqual(result?.watchedPercent, 50)
        XCTAssertEqual(result?.item.sourceAccountID, fixture.account.id)
        XCTAssertNil(restored.receipt)
    }

    func testInvalidCallbacksDoNotWriteProgress() async throws {
        for position in ["NaN", "inf", "-1", "9999999999", "800", ""] {
            let fixture = ExternalPlaybackFixture()
            defer { fixture.cleanup() }
            _ = try await fixture.launch()
            fixture.runtime.receive(try fixture.callback(position: position))
            await fixture.runtime.processReturn(context: { fixture.context }) { _ in XCTFail("Invalid result") }
            XCTAssertEqual(fixture.runtime.error, .invalidCallback)
            XCTAssertNil(fixture.runtime.receipt)
        }
    }

    func testWrongURLDuplicateFieldsExpiredAndSupersededCallbacksAreRejected() async throws {
        for mode in 0..<4 {
            let fixture = ExternalPlaybackFixture()
            defer { fixture.cleanup() }
            _ = try await fixture.launch()
            var callback = try XCTUnwrap(URLComponents(url: fixture.callback(position: "300"), resolvingAgainstBaseURL: false))
            if mode == 0 {
                callback.queryItems?.removeAll { $0.name == "lastPlayedUrl" }
                callback.queryItems?.append(.init(name: "lastPlayedUrl", value: "https://wrong.test/video"))
            } else if mode == 1 {
                callback.queryItems?.append(.init(name: "position", value: "20"))
            } else if mode == 3 {
                fixture.runtime.beginPlaybackIntent()
            }
            fixture.runtime.receive(
                try XCTUnwrap(callback.url),
                now: mode == 2 ? Date().addingTimeInterval(86_401) : Date()
            )
            await fixture.runtime.processReturn(context: { fixture.context }) { _ in XCTFail("Rejected callback") }
            XCTAssertNil(fixture.runtime.receipt)
        }
    }

    func testZeroPositionIsValidAndCallbackReplayIsIgnored() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        let callback = try fixture.callback(position: "0")
        fixture.runtime.receive(callback)
        fixture.runtime.receive(try fixture.callback(position: "600"))
        var count = 0
        await fixture.runtime.processReturn(context: { fixture.context }) {
            count += 1
            XCTAssertEqual($0.position, 0)
            XCTAssertEqual($0.watchedPercent, 0)
        }
        fixture.runtime.receive(callback)
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in count += 1 }
        XCTAssertEqual(count, 1)
    }

    func testReceiptIsRetainedUntilDurableOutboxAcceptsIt() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        fixture.runtime.receive(try fixture.callback(position: "300"))
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in
            throw ExternalPlayerError.persistence
        }
        XCTAssertNotNil(fixture.runtime.returnID)
        XCTAssertEqual(fixture.runtime.error, .progressSyncFailed)
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in }
        XCTAssertNil(fixture.runtime.receipt)
    }

    func testFailureCallbackNeverUsesThirdPartyErrorTextOrCreatesProgress() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.launch()
        var callback = try XCTUnwrap(URLComponents(url: fixture.callback(position: "300"), resolvingAgainstBaseURL: false))
        callback.path = "/error"
        callback.queryItems?.append(.init(name: "errorMessage", value: "synthetic-token"))
        fixture.runtime.receive(try XCTUnwrap(callback.url))
        await fixture.runtime.processReturn(context: { fixture.context }) { _ in XCTFail("Player failure") }
        XCTAssertEqual(fixture.runtime.error, .playbackFailed)
        XCTAssertNil(fixture.runtime.receipt)
    }

    func testVLCLaunchDoesNotPromiseAProgressReceipt() async throws {
        let fixture = ExternalPlaybackFixture()
        defer { fixture.cleanup() }
        fixture.settings.externalPlayer.player = .vlc
        _ = try await fixture.launch()
        XCTAssertNil(fixture.runtime.receipt)
    }
}

@MainActor
private final class ExternalPlaybackFixture {
    let suite = "ExternalPlaybackRuntimeTests.\(UUID().uuidString)"
    let media = URL(string: "https://server.test/movie.mkv?token=synthetic-token")!
    let callbackScheme = "com.test.external-player"
    lazy var defaults = UserDefaults(suiteName: suite)!
    lazy var runtime = ExternalPlaybackRuntime(
        defaults: defaults, callbackScheme: callbackScheme,
        canOpen: { [unowned self] _ in installed },
        open: { [unowned self] url in opened.append(url); return openSucceeds }
    )
    var profileID = "profile"
    var userID = "user"
    var authorized = true
    var installed = true
    var openSucceeds = true
    var opened: [URL] = []
    var selectedVersion: String?
    var releasedSessions = 0
    var beforeRequest: (@MainActor () -> Void)?
    var beforeItem: (@MainActor () -> Void)?
    var offlineResolver: (any OfflinePlaybackResolving)?
    var item = MediaItem(
        id: "movie", title: "Fixture movie", kind: .movie, runtime: 600,
        sourceAccountID: "account", selectedVersionID: "version-one"
    )
    lazy var request = PlaybackRequest(item: item, streamURL: media, startPosition: 120)
    var settings = PlaybackSettings(externalPlayer: .init(player: .infuse))
    lazy var account = Account(id: "account", from: session)
    var session: UserSession {
        UserSession(
            server: MediaServer(id: "server", name: "Fixture", baseURL: URL(string: "https://server.test")!, provider: .jellyfin),
            userID: userID, userName: "Fixture", deviceID: "fixture", accessToken: "synthetic-token"
        )
    }
    var context: ExternalPlaybackContext {
        ExternalPlaybackContext(
            profileID: profileID, authorizationID: "authorization", accounts: [
                ResolvedAccount(account: account, provider: ExternalPlaybackProvider(session: session, fixture: self))
            ], isAuthorized: authorized, resolver: ExternalPlaybackResolver(url: media),
            offlineResolver: offlineResolver
        )
    }
    func launch() async throws -> Bool {
        runtime.beginPlaybackIntent()
        return try await runtime.launch(
            item: item, startPosition: 120, settings: settings,
            context: { self.context }, isPresented: { true }
        )
    }
    func callback(position: String) throws -> URL {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = "external-player"
        components.path = "/success"
        components.queryItems = [
            .init(name: "session", value: try XCTUnwrap(runtime.receipt?.id.uuidString)),
            .init(name: "position", value: position),
            .init(name: "lastPlayedUrl", value: media.absoluteString)
        ]
        return try XCTUnwrap(components.url)
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}

private struct ExternalPlaybackResolver: AuthenticatedHTTPResourceResolving {
    let url: URL
    func resolve(_ locator: AuthenticatedHTTPPlaybackLocator) async throws -> URL { url }
}

private struct ExternalOfflineResolver: OfflinePlaybackResolving {
    func localPlaybackURL(for item: MediaItem, versionID: String?) async -> URL? {
        URL(fileURLWithPath: "/private/offline/video.mkv")
    }
}

private struct ExternalPlaybackProvider: StreamingQualityProviding {
    let kind: ProviderKind = .jellyfin
    let session: UserSession
    let fixture: ExternalPlaybackFixture
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem {
        await MainActor.run {
            fixture.beforeItem?()
            return fixture.item
        }
    }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { await fixture.request }
    func playbackInfo(for itemID: String, mediaSourceID: String?, forceTranscode: Bool) async throws -> PlaybackRequest {
        await MainActor.run {
            fixture.selectedVersion = mediaSourceID
            fixture.beforeRequest?()
            return fixture.request
        }
    }
    func playbackInfo(
        for itemID: String, mediaSourceID: String?, forceTranscode: Bool, streaming: StreamingPlaybackOptions
    ) async throws -> PlaybackRequest { await fixture.request }
    func releaseStreamingSession(_ request: PlaybackRequest) async { await MainActor.run { fixture.releasedSessions += 1 } }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
