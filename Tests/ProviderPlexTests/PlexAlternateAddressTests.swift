import CoreModels
import CoreNetworking
import Foundation
import XCTest
@testable import ProviderPlex

final class PlexAlternateAddressTests: XCTestCase {
    func testDiscoveryRefreshRetainsApprovedManualAddress() async throws {
        let id = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "plex.reachable.\(id)")
            UserDefaults.standard.removeObject(forKey: "plex.artwork-origins.\(id)")
        }
        let original = URL(string: "https://offline.test")!
        let manual = URL(string: "http://192.168.1.50:32400")!
        let server = MediaServer(id: id, name: "Home", baseURL: original, provider: .plex,
                                 connectionURLs: [original], alternateConnectionURLs: [manual])
        let http = PlexAddressHTTP(manual: manual)
        let provider = PlexProvider(session: UserSession(server: server, userID: "owner", userName: "Viewer",
                                                         deviceID: "device", accessToken: "credential"),
                                    http: http, connectionRefresh: { [] }, probe: http)
        let selected = try await provider.resolveAuthenticatedHTTPOrigin()
        XCTAssertEqual(selected, manual)
        let probes = await http.requests
        XCTAssertEqual(probes.filter { $0.0 == manual }.count, 2)
        XCTAssertTrue(probes.allSatisfy { $0.1.redirectPolicy == .sameOrigin })
    }
}

private actor PlexAddressHTTP: HTTPClient {
    let manual: URL
    var requests: [(URL, Endpoint)] = []
    init(manual: URL) { self.manual = manual }
    func send(_ endpoint: Endpoint, baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        requests.append((baseURL, endpoint))
        guard baseURL == manual, requests.filter({ $0.0 == manual }).count > 1 else {
            throw AppError.serverUnreachable
        }
        return (Data(), HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
