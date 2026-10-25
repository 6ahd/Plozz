import Foundation
import CoreModels
import CoreNetworking

/// Low-level calls to Nuvio's Supabase backend: GoTrue auth (`/auth/v1`),
/// PostgREST RPCs (`/rest/v1/rpc`) and the TV-login exchange function.
///
/// The request shapes follow Nuvio's own TV client, as Dex Hub (Kodi) does.
/// Plozz identifies itself honestly in the User-Agent and device name and never
/// impersonates the official apps.
struct NuvioClient: Sendable {
    let config: NuvioConfig
    let http: HTTPClient

    private var anonKey: String { config.anonKey ?? "" }

    // MARK: - TV login

    /// An anonymous session that may start and poll a TV login.
    func anonymousSession(clientID: String) async throws -> String {
        let signup = try? await sendJSON(
            path: "/auth/v1/signup",
            body: ["data": ["tv_client": "plozz", "sync_client_id": clientID]],
            bearer: anonKey
        )
        if let token = (signup as? [String: Any])?["access_token"] as? String, !token.isEmpty {
            return token
        }
        let json = try await sendJSON(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "anonymous")],
            body: [String: Any](),
            bearer: anonKey
        )
        guard let token = (json as? [String: Any])?["access_token"] as? String, !token.isEmpty else {
            throw AppError.invalidResponse
        }
        return token
    }

    func startTVLogin(anonToken: String, nonce: String, deviceName: String) async throws -> NuvioTVLogin {
        let json = try await rpc("start_tv_login_session", [
            "p_device_nonce": nonce,
            "p_redirect_base_url": config.loginPageURL.absoluteString,
            "p_device_name": deviceName
        ], bearer: anonToken)
        let row = Self.firstRow(json)
        guard let code = (row["code"] as? String)?.trimmingCharacters(in: .whitespaces), !code.isEmpty else {
            throw AppError.invalidResponse
        }
        var url = (row["qr_content"] as? String) ?? (row["web_url"] as? String) ?? ""
        if url.isEmpty {
            var components = URLComponents(url: config.loginPageURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "code", value: code)]
            url = components?.url?.absoluteString ?? config.loginPageURL.absoluteString
        }
        let poll = Self.number(row["poll_interval_seconds"]) ?? 3
        return NuvioTVLogin(
            code: code, url: url, nonce: nonce, anonToken: anonToken,
            pollInterval: min(max(poll, 2), 5)
        )
    }

    func pollTVLogin(_ login: NuvioTVLogin) async throws -> NuvioLoginPoll {
        let json = try await rpc("poll_tv_login_session", [
            "p_code": login.code,
            "p_device_nonce": login.nonce
        ], bearer: login.anonToken)
        let status = ((Self.firstRow(json)["status"] as? String) ?? "pending").lowercased()
        switch status {
        case "approved", "authorized", "completed": return .approved
        case "expired", "cancelled", "canceled", "consumed": return .expired
        default: return .pending
        }
    }

    func exchangeTVLogin(_ login: NuvioTVLogin) async throws -> NuvioTokens {
        let json = try await sendJSON(
            path: "/functions/v1/tv-logins-exchange",
            body: ["code": login.code, "device_nonce": login.nonce],
            bearer: login.anonToken
        )
        return try Self.tokens(from: json as? [String: Any] ?? [:])
    }

    // MARK: - Session

    func refresh(_ refreshToken: String) async throws -> NuvioTokens {
        let json = try await sendJSON(
            path: "/auth/v1/token",
            query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken],
            bearer: nil
        )
        return try Self.tokens(from: json as? [String: Any] ?? [:])
    }

    func profiles(accessToken: String) async throws -> [NuvioProfile] {
        let json = try await rpc("sync_pull_profiles", [:], bearer: accessToken)
        let rows = json as? [[String: Any]] ?? []
        return rows.compactMap { row in
            let raw = row["profile_index"] ?? row["profileIndex"] ?? row["index"]
            let index = (raw as? Int) ?? (raw as? String).flatMap(Int.init)
            guard let index, index > 0 else { return nil }
            let name = (row["name"] as? String) ?? (row["title"] as? String) ?? ""
            return NuvioProfile(index: index, name: name.isEmpty ? "Profile \(index)" : name)
        }
        .sorted { $0.index < $1.index }
    }

    // MARK: - Watch progress

    func pushProgress(
        _ entries: [NuvioProgressEntry], profileIndex: Int, clientID: String, accessToken: String
    ) async throws {
        let encoded = try JSONEncoder().encode(entries)
        let rows = try JSONSerialization.jsonObject(with: encoded)
        _ = try await rpc("sync_push_watch_progress", [
            "p_profile_id": profileIndex,
            "p_entries": rows,
            "p_origin_client_id": clientID
        ], bearer: accessToken)
    }

    // MARK: - Transport

    private func rpc(_ function: String, _ params: [String: Any], bearer: String) async throws -> Any {
        try await sendJSON(path: "/rest/v1/rpc/\(function)", body: params, bearer: bearer)
    }

    private func sendJSON(
        path: String, query: [URLQueryItem] = [], body: Any, bearer: String?
    ) async throws -> Any {
        var headers = [
            "apikey": anonKey,
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "Plozz Nuvio Sync"
        ]
        if let bearer { headers["Authorization"] = "Bearer \(bearer)" }
        let endpoint = Endpoint(
            method: .post,
            path: path,
            queryItems: query,
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: body),
            redirectPolicy: .sameOrigin
        )
        let (data, _) = try await http.send(endpoint, baseURL: config.apiBaseURL)
        guard !data.isEmpty else { return [String: Any]() }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? [String: Any]()
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return (value as? String).flatMap(Double.init)
    }

    private static func firstRow(_ json: Any) -> [String: Any] {
        if let rows = json as? [[String: Any]] { return rows.first ?? [:] }
        return json as? [String: Any] ?? [:]
    }

    /// Reads a GoTrue session, flat or nested under `session`.
    static func tokens(from json: [String: Any]) throws -> NuvioTokens {
        let session = json["session"] as? [String: Any] ?? [:]
        guard let access = (json["access_token"] as? String) ?? (session["access_token"] as? String),
              !access.isEmpty else {
            throw AppError.invalidResponse
        }
        let refresh = (json["refresh_token"] as? String) ?? (session["refresh_token"] as? String)
        let expiresIn = number(json["expires_in"]) ?? number(session["expires_in"]) ?? 3600
        let user = (json["user"] as? [String: Any]) ?? (session["user"] as? [String: Any]) ?? [:]
        return NuvioTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn),
            email: user["email"] as? String
        )
    }
}
