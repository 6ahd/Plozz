import AetherEngine
import CoreModels
import Foundation
import XCTest
@testable import EnginePlozzigen

final class PlozzigenPlaybackFailureTests: XCTestCase {
    func testHTTPRefusalRetainsStatusAndNeverBecomesACodecFailure() throws {
        for (status, kind) in [
            (401, StreamingPlaybackFailure.Kind.accessDenied), (403, .accessDenied),
            (404, .unavailable), (410, .unavailable), (429, .rateLimited),
            (451, .accessRestricted), (500, .server), (504, .timedOut)
        ] {
            let info = PlaybackErrorInfo(
                kind: .sourceRefused, message: "https://private.test?token=secret", underlyingCode: status
            )
            let failure = try XCTUnwrap(PlozzigenPlaybackFailure.classify(info))
            XCTAssertEqual(failure.kind, kind)
            XCTAssertEqual(failure.diagnosticCode, "HTTP \(status)")
            XCTAssertFalse(failure.allowsCodecFallback)
            XCTAssertFalse(String(localized: failure.userMessage).contains("secret"))
        }
    }

    func testRateLimitingStorageAndAudioFailuresHaveSpecificRecovery() throws {
        for (engineKind, kind) in [
            (PlaybackErrorKind.sourceRateLimited, StreamingPlaybackFailure.Kind.rateLimited),
            (.storageExhausted, .storageExhausted), (.audioSessionFailed, .audioOutputFailed)
        ] {
            let failure = try XCTUnwrap(PlozzigenPlaybackFailure.classify(
                .init(kind: engineKind, message: "private failure")
            ))
            XCTAssertEqual(failure.kind, kind)
            XCTAssertFalse(failure.allowsCodecFallback)
        }
    }

    func testDecoderFailureStillAllowsCompatibilityFallback() {
        let failure = PlozzigenPlaybackFailure.classify(.init(kind: .softwarePipelineFailed, message: "private"))
        XCTAssertEqual(failure?.kind, .unsupportedFormat)
        XCTAssertEqual(failure?.allowsCodecFallback, true)
    }

    func testCertificateFailureUsesTypedEvidenceNotMessage() {
        let failure = PlozzigenPlaybackFailure.classify(.init(
            kind: .sourceCertificateRejected, message: "localized failure",
            underlyingDomain: NSURLErrorDomain, underlyingCode: URLError.serverCertificateUntrusted.rawValue
        ))
        XCTAssertEqual(failure?.kind, .network)
        XCTAssertEqual(failure?.diagnosticCode, "URL -1202")
        XCTAssertEqual(failure?.allowsCodecFallback, false)
    }

    func testUnknownTextAndDomainCannotInventHTTPOrLeakSecrets() {
        let failure = PlozzigenPlaybackFailure.classify(.init(
            kind: .sourceOpenFailed, message: "HTTP 410 https://private.test?token=secret",
            underlyingDomain: "private-domain", underlyingCode: 410
        ))
        XCTAssertEqual(failure?.kind, .unknown)
        XCTAssertNil(failure?.httpStatus)
        XCTAssertNil(failure?.diagnosticCode)
    }
}
