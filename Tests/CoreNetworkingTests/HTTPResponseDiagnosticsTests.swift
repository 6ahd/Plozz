import CoreModels
import Foundation
import XCTest
@testable import CoreNetworking
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class HTTPResponseDiagnosticsTests: XCTestCase {
    private struct Envelope: Decodable, Sendable {
        struct Item: Decodable, Sendable { let Id: String }
        let Items: [Item]
    }

    func testCapturePreservesAppErrorAndResponseStructureWithoutPrivateValues() async throws {
        let captured = await HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: #"{"Items":[{"Id":false}],"private-key":"private-value"}"#).decode(
                Envelope.self, from: Endpoint(path: "/private-path", headers: ["Authorization": "private-token"]),
                baseURL: URL(string: "https://private-host.invalid")!
            )
        }
        guard case .failure(let error) = captured.result else { return XCTFail("Expected decoding failure") }
        XCTAssertEqual(error as? AppError, .decoding)
        let response = try XCTUnwrap(captured.responses.first)
        XCTAssertEqual(response.httpStatus, 200)
        XCTAssertEqual(response.payload, .object)
        XCTAssertEqual(response.reason, .wrongType)
        XCTAssertEqual(response.path, "Items.[0].Id")
        XCTAssertEqual(response.expected, .string)
        let report = LibraryRecommendationDiagnostic(
            provider: .plex, failures: [.init(section: .recommendations, error: .decoding, responses: captured.responses)]
        )
        XCTAssertFalse(report.supportText.contains("private"))
    }

    func testConcurrentScopesDoNotMixResponsesAndSuccessfulFallbackDiscardsFailures() async throws {
        async let object = HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: #"{"Items":false}"#).decode(
                Envelope.self, from: Endpoint(path: "/a"), baseURL: URL(string: "https://fixture.invalid")!
            )
        }
        async let html = HTTPResponseDiagnostics.capture {
            try await FixtureHTTP(json: "<html>private response</html>").decode(
                Envelope.self, from: Endpoint(path: "/b"), baseURL: URL(string: "https://fixture.invalid")!
            )
        }
        let (first, second) = await (object, html)
        XCTAssertEqual(first.responses.map(\.payload), [.object])
        XCTAssertEqual(second.responses.map(\.payload), [.nonJSON])
        let recovered = await HTTPResponseDiagnostics.capture {
            do {
                return try await FixtureHTTP(json: "{}").decode(
                    Envelope.self, from: Endpoint(path: "/fallback"), baseURL: URL(string: "https://fixture.invalid")!
                )
            } catch AppError.decoding {
                return Envelope(Items: [])
            }
        }
        XCTAssertTrue(recovered.responses.isEmpty)
        XCTAssertNotNil(try? recovered.result.get())
    }

    func testDynamicCodingKeysAndDescriptionsNeverEnterSupportReport() throws {
        struct DynamicKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let key = try XCTUnwrap(DynamicKey(stringValue: "https://private.invalid/?token=secret"))
        let error = DecodingError.keyNotFound(key, .init(codingPath: [], debugDescription: "private secret"))
        let response = ResponseDecodingDiagnostic(
            route: .other, httpStatus: 200, bytes: 20, payload: .object, error: error
        )
        XCTAssertEqual(response.path, "<field>")
        let report = PlaybackDiagnosticReport.library(.init(provider: .jellyfin, failures: [
            .init(section: .recentlyAdded, error: .unknown("private secret"), responses: [response])
        ]))
        XCTAssertTrue(report.supportText.contains("failure_0.reason=unknown"))
        XCTAssertFalse(report.supportText.contains("private"))
        XCTAssertFalse(report.supportText.contains("secret"))
    }

    func testFailureCaptureIsBoundedAndMissingKeysStayActionable() async throws {
        let captured = await HTTPResponseDiagnostics.capture { () async throws -> Envelope in
            for _ in 0..<7 {
                do {
                    _ = try await FixtureHTTP(json: "{}").decode(
                        Envelope.self, from: Endpoint(path: "/fixture"), baseURL: URL(string: "https://fixture.invalid")!
                    )
                } catch AppError.decoding {
                    continue
                }
            }
            throw AppError.decoding
        }
        XCTAssertEqual(captured.responses.count, 4)
        XCTAssertEqual(captured.responses.last?.reason, .missingKey)
        XCTAssertEqual(captured.responses.last?.path, "Items")
    }

    private struct FixtureHTTP: HTTPClient {
        let json: String
        func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }
}
