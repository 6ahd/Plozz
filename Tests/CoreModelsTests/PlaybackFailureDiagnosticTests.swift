import CoreModels
import Foundation
import XCTest

final class PlaybackFailureDiagnosticTests: XCTestCase {
    func testLocalPlaybackEvidenceDoesNotEnableRemoteReporting() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let attempt = try XCTUnwrap(diagnostics.begin(
            layer: .liveEngine, content: .live, captureForPresentation: true
        ))
        let buffer = PlaybackFailureBuffer()
        diagnostics.start { buffer.append($0) }
        attempt.fail(stage: .load, reason: .network, domain: .url, code: -1001)
        XCTAssertTrue(buffer.values.isEmpty)
        XCTAssertEqual(attempt.diagnostic?.code, -1001)
        let report = LiveChannelFailureReport(failure: .engine(.serverUnreachable), diagnostic: attempt.diagnostic)
        XCTAssertTrue(String(localized: report.message).contains("did not respond in time"))
        XCTAssertFalse(LiveTVDiagnosticReport.playback(report).supportText.contains("http_status"))
    }

    func testSupportReportNeverExportsUnknownErrorDescriptions() {
        let privateDescription = "https://private.invalid/live/user/password?token=private-secret"
        let report = LiveChannelFailureReport(failure: .engine(.unknown(privateDescription)))
        XCTAssertEqual(LiveTVDiagnosticReport.playback(report).supportText,
                       "format=plozz-live-tv-1\noperation=playback\nfailure=unknown")
        XCTAssertFalse(String(localized: report.message).contains("private"))
    }

    func testTerminalDeliveryReportKeepsMatchingStatusAfterAnEarlierRecoverableFailure() throws {
        let attempt = try XCTUnwrap(PlaybackFailureDiagnostics().begin(
            layer: .iptvProxy, content: .live, captureForPresentation: true
        ))
        attempt.fail(stage: .response, reason: .notFound, httpStatus: 404)
        let refusal = attempt.fail(stage: .response, reason: .authentication, httpStatus: 403)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:12345/fixture"))
        let delivery = PlaybackDeliveryFailure.register(loopbackURL: url)
        defer { PlaybackDeliveryFailure.unregister(loopbackURL: url) }
        delivery.record(.unauthorized, diagnostic: refusal)
        XCTAssertEqual(delivery.diagnostic?.httpStatus, 403)
        XCTAssertEqual(attempt.diagnostic?.httpStatus, 404, "Remote diagnostics still record only the first failure.")
    }

    func testConsentRevocationDiscardsRetainedAttemptsEvenAfterReenabling() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let buffer = PlaybackFailureBuffer()
        XCTAssertNil(diagnostics.begin(layer: .iptvProxy, content: .live))
        diagnostics.start { buffer.append($0) }
        let stale = try XCTUnwrap(diagnostics.begin(layer: .iptvProxy, content: .live))
        diagnostics.stop()
        diagnostics.start { buffer.append($0) }
        stale.fail(stage: .response, reason: .authentication, httpStatus: 403)
        XCTAssertTrue(buffer.values.isEmpty)
        let current = try XCTUnwrap(diagnostics.begin(layer: .iptvProxy, content: .live))
        current.fail(stage: .response, reason: .authentication, httpStatus: 403)
        current.fail(stage: .body, reason: .network)
        XCTAssertEqual(buffer.values.count, 1)
        XCTAssertEqual(buffer.values.first?.httpStatus, 403)
    }

    func testCancellationAndUnboundedCodesCannotBecomeFailureReports() throws {
        let diagnostics = PlaybackFailureDiagnostics()
        let buffer = PlaybackFailureBuffer()
        diagnostics.start { buffer.append($0) }
        let attempt = try XCTUnwrap(diagnostics.begin(layer: .liveEngine, content: .live))
        attempt.fail(stage: .load, reason: .cancelled)
        XCTAssertTrue(buffer.values.isEmpty)
        attempt.fail(stage: .playback, engineFailure: .nativeItemFailed, domain: .avfoundation,
                     code: Int.max, httpStatus: Int.max)
        let diagnostic = try XCTUnwrap(buffer.values.first)
        XCTAssertNil(diagnostic.code)
        XCTAssertNil(diagnostic.httpStatus)
        XCTAssertTrue(diagnostic.isValid)
        XCTAssertEqual(diagnostic.engineFailure, .nativeItemFailed)
    }

    func testUnknownContentTypesAndDomainsNeverRetainFreeFormValues() {
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "video/MP2T; private=secret"), .transportStream)
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "text/html"), .html)
        XCTAssertEqual(PlaybackFailureDiagnostic.Format(mimeType: "https://private.test"), .other)
        XCTAssertEqual(PlaybackFailureDiagnostic.Domain("https://private.test"), .other)
    }
}

private final class PlaybackFailureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [PlaybackFailureDiagnostic] = []
    var values: [PlaybackFailureDiagnostic] { lock.withLock { storage } }
    func append(_ value: PlaybackFailureDiagnostic) { lock.withLock { storage.append(value) } }
}
