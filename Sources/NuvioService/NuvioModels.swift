import Foundation

// MARK: - Stored session

/// Persisted after a successful Nuvio TV login. Supabase access tokens last
/// about an hour; the refresh token renews them. The selected Nuvio profile is
/// kept with the session because every sync RPC is scoped to one profile.
public struct NuvioTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var email: String?
    public var profileIndex: Int?
    public var profileName: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        email: String? = nil,
        profileIndex: Int? = nil,
        profileName: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.email = email
        self.profileIndex = profileIndex
        self.profileName = profileName
    }

    /// Refresh a minute early so a request never races the expiry.
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 60 }

    /// What Settings shows for the connection.
    public var displayName: String {
        let account = email.flatMap { $0.isEmpty ? nil : $0 } ?? "Nuvio"
        guard let profileName, !profileName.isEmpty else { return account }
        return "\(account) · \(profileName)"
    }
}

/// One profile on a Nuvio account (`sync_pull_profiles`).
public struct NuvioProfile: Sendable, Equatable, Identifiable {
    public var index: Int
    public var name: String
    public var id: Int { index }

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}

// MARK: - TV login

/// A pending TV login: the QR/web URL the user approves on their phone, plus
/// the nonce and anonymous session needed to poll and exchange it.
public struct NuvioTVLogin: Sendable, Equatable {
    public var code: String
    public var url: String
    var nonce: String
    var anonToken: String
    var pollInterval: TimeInterval
}

enum NuvioLoginPoll: Sendable, Equatable {
    case pending
    case approved
    case expired
}

// MARK: - Watch progress

/// The exact row shape Nuvio's own apps push with `sync_push_watch_progress`.
/// Times are milliseconds; an episode's key is `<id>_s<S>e<E>`, a film's `<id>`.
struct NuvioProgressEntry: Encodable, Sendable, Equatable {
    var contentID: String
    var contentType: String
    var videoID: String
    var season: Int?
    var episode: Int?
    var position: Int64
    var duration: Int64
    var lastWatched: Int64
    var progressKey: String

    enum CodingKeys: String, CodingKey {
        case contentID = "content_id"
        case contentType = "content_type"
        case videoID = "video_id"
        case season, episode, position, duration
        case lastWatched = "last_watched"
        case progressKey = "progress_key"
    }

    // Nuvio's apps send an explicit null season/episode for films.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contentID, forKey: .contentID)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(videoID, forKey: .videoID)
        try c.encode(season, forKey: .season)
        try c.encode(episode, forKey: .episode)
        try c.encode(position, forKey: .position)
        try c.encode(duration, forKey: .duration)
        try c.encode(lastWatched, forKey: .lastWatched)
        try c.encode(progressKey, forKey: .progressKey)
    }
}
