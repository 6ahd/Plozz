import CoreModels
import Foundation
import XCTest
@testable import EnginePlozzigen

final class PlozzigenLiveSourceProbeTests: XCTestCase {
    func testOpaqueHTTPAddressesRequireContentInspection() throws {
        for address in ["https://example.test/channel", "http://example.test/live.php?id=1"] {
            XCTAssertTrue(PlozzigenLiveSourceProbe.isRequired(for: try XCTUnwrap(URL(string: address))))
        }
        for address in ["https://example.test/channel.m3u8", "https://example.test/channel.TS",
                        "https://example.test/channel.m2ts", "file:///channel"] {
            XCTAssertFalse(PlozzigenLiveSourceProbe.isRequired(for: try XCTUnwrap(URL(string: address))))
        }
    }

    func testManifestBytesIdentifyNativeHLSIncludingBOMAndLeadingWhitespace() {
        for prefix in ["#EXTM3U\n", "#EXTM3U\r\n", "\u{FEFF} \n#EXTM3U\n"] {
            XCTAssertEqual(PlozzigenLiveSourceProbe.recognizedFormat(Data(prefix.utf8)), .hls)
        }
        XCTAssertNil(PlozzigenLiveSourceProbe.recognizedFormat(Data("#EXTM3U-not-a-playlist".utf8)))
        XCTAssertNil(PlozzigenLiveSourceProbe.recognizedFormat(Data("<html>not media</html>".utf8)))
    }

    func testTransportStreamRequiresThreeFramedSyncBytes() {
        for (stride, offset) in [(188, 0), (192, 4), (204, 0)] {
            var prefix = Data(repeating: 0, count: offset + 2 * stride + 1)
            for index in 0..<3 { prefix[offset + stride * index] = 0x47 }
            XCTAssertEqual(PlozzigenLiveSourceProbe.recognizedFormat(prefix), .transportStream)
            prefix[offset + stride] = 0
            XCTAssertNil(PlozzigenLiveSourceProbe.recognizedFormat(prefix))
        }
        XCTAssertNil(PlozzigenLiveSourceProbe.recognizedFormat(Data([0x47])))
    }

    func testCrossOriginRedirectNeverForwardsAccountHeadersEvenWhenReturningToOrigin() throws {
        let origin = try XCTUnwrap(URL(string: "https://account.test/live"))
        let delivery = try XCTUnwrap(URL(string: "http://delivery.test/channel?issued=opaque"))
        var request = URLRequest(url: delivery)
        request.setValue("private", forHTTPHeaderField: "Authorization")
        request.setValue("private", forHTTPHeaderField: "Cookie")
        request.setValue("private", forHTTPHeaderField: "X-Provider-Key")
        let clean = try XCTUnwrap(PlozzigenLiveSourceProbe.redirect(request, previous: origin, original: origin))
        XCTAssertEqual(clean.url, delivery)
        XCTAssertEqual(clean.allHTTPHeaderFields, ["Accept-Encoding": "identity"])
        request.url = origin
        let returning = try XCTUnwrap(PlozzigenLiveSourceProbe.redirect(
            request, previous: delivery, original: origin
        ))
        XCTAssertEqual(returning.allHTTPHeaderFields, ["Accept-Encoding": "identity"])
        let sameOrigin = try XCTUnwrap(PlozzigenLiveSourceProbe.redirect(
            request, previous: origin, original: origin
        ))
        XCTAssertEqual(sameOrigin.value(forHTTPHeaderField: "Authorization"), "private")
        request.url = URL(string: "file:///etc/passwd")
        XCTAssertNil(PlozzigenLiveSourceProbe.redirect(request, previous: origin, original: origin))
    }

    func testProbeHasFiniteDeadlineAndNoPersistentHTTPState() {
        let configuration = URLSessionConfiguration.default
        let probe = PlozzigenLiveSourceProbe(configuration: configuration)
        defer { probe.cancel() }
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 15)
        XCTAssertEqual(PlozzigenLiveSourceProbe.maximumBytes, 1_024)
    }

    func testPreloadErrorsStayTypedWithoutNativeItemEvidence() {
        XCTAssertEqual(PlozzigenLiveFailure.appError(nil, fallbackError: AppError.accessRestricted), .accessRestricted)
        XCTAssertEqual(PlozzigenLiveFailure.appError(nil, fallbackError: URLError(.timedOut)), .serverUnreachable)
        XCTAssertEqual(PlozzigenLiveFailure.appError(nil, fallbackError: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(
            PlozzigenLiveFailure.appError(nil, deliveryFailure: .unauthorized, fallbackError: AppError.invalidResponse),
            .unauthorized
        )
    }
}
