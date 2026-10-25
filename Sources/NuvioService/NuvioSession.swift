import Foundation
import CoreModels
import CoreNetworking

/// Hands out a valid access token for the stored Nuvio session, refreshing it
/// when it is about to expire. Shared by the Settings façade and the scrobbler.
struct NuvioSession: Sendable {
    let client: NuvioClient
    let tokenStore: NuvioTokenStoring

    func validTokens() async throws -> NuvioTokens {
        guard let tokens = tokenStore.load() else { throw AppError.unauthorized }
        guard tokens.needsRefresh else { return tokens }
        guard let refreshToken = tokens.refreshToken else { throw AppError.unauthorized }
        var fresh: NuvioTokens
        do {
            fresh = try await client.refresh(refreshToken)
        } catch AppError.invalidResponse {
            // GoTrue answers a revoked or reused refresh token with 400.
            throw AppError.unauthorized
        }
        // A sign-out or another account while refreshing wins over this result.
        guard let latest = tokenStore.load(), latest.refreshToken == refreshToken else {
            if let latest = tokenStore.load() { return latest }
            throw AppError.unauthorized
        }
        fresh.email = fresh.email ?? latest.email
        fresh.refreshToken = fresh.refreshToken ?? latest.refreshToken
        fresh.profileIndex = latest.profileIndex
        fresh.profileName = latest.profileName
        try? tokenStore.save(fresh)
        return fresh
    }
}

/// The per-install origin id Nuvio uses so a client's own writes are not echoed
/// back to it. Stable across launches; prefixed so Nuvio can tell Plozz apart.
enum NuvioClientIdentity {
    private static let key = "nuvio.syncClientID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: key), saved.count >= 16 { return saved }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let suffix = String((0..<32).map { _ in alphabet.randomElement()! })
        let id = "plozz-\(suffix)"
        defaults.set(id, forKey: key)
        return id
    }

    static func nonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
