import Foundation
import CoreModels
import CoreNetworking

/// Sends Plozz playback progress to Nuvio so Nuvio's Continue Watching (phone,
/// TV, web) picks up where Plozz left off. Best-effort: failures are logged and
/// never reach playback.
public protocol NuvioScrobbling: Sendable {
    func scrobble(item: MediaItem, progress: Double, event: PlaybackEvent) async
}

/// No-op scrobbler when Nuvio is unconfigured.
public struct DisabledNuvioScrobbler: NuvioScrobbling {
    public init() {}
    public func scrobble(item: MediaItem, progress: Double, event: PlaybackEvent) async {}
}

/// Live Nuvio scrobbler.
///
/// Only pause and stop are written: that is when the resume point changes in a
/// way another device cares about, and it keeps Plozz well inside Nuvio's
/// request budget. A rate-limited reply pauses writes until it expires.
public actor NuvioScrobbler: NuvioScrobbling {
    private let client: NuvioClient
    private let session: NuvioSession
    private var cooldownUntil: Date?

    /// Nuvio treats a title as finished (out of Continue Watching) at a full
    /// position; Plozz marks watched at the same point the other trackers do.
    static let finishedPercent: Double = 90

    public init(config: NuvioConfig, http: HTTPClient, tokenStore: NuvioTokenStoring) {
        let client = NuvioClient(config: config, http: http)
        self.client = client
        self.session = NuvioSession(client: client, tokenStore: tokenStore)
    }

    public func scrobble(item: MediaItem, progress: Double, event: PlaybackEvent) async {
        guard event == .pause || event == .stop else { return }
        if let cooldownUntil, cooldownUntil > Date() { return }
        guard let entry = Self.entry(for: item, progress: progress, now: Date()) else {
            FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "skip(no usable ids or runtime)"))
            return
        }
        do {
            let tokens = try await session.validTokens()
            guard let profile = tokens.profileIndex else {
                FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "skip(no profile)"))
                return
            }
            try await client.pushProgress(
                [entry], profileIndex: profile,
                clientID: NuvioClientIdentity.current(), accessToken: tokens.accessToken
            )
            FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "OK(\(event))"))
        } catch AppError.rateLimited(let retryAfter) {
            cooldownUntil = Date().addingTimeInterval(max(retryAfter ?? 0, 15 * 60))
            FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "rate-limited"))
        } catch AppError.unauthorized {
            FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "skip(not connected)"))
        } catch {
            FanoutDiagnostics.emit(FanoutDiagnostics.scrobbleLine(tracker: "nuvio", item: item, outcome: "THROW(\(error))"))
        }
    }

    // MARK: - Mapping

    /// Builds Nuvio's progress row. Nuvio keys content by IMDb id (or
    /// `tmdb:<id>`): a film by its own id, an episode by its series id plus
    /// season and episode. Media without such an id, or without a known
    /// runtime, cannot be placed in Nuvio and is skipped.
    static func entry(for item: MediaItem, progress: Double, now: Date) -> NuvioProgressEntry? {
        guard let runtime = item.runtime, runtime > 0 else { return nil }
        let percent = min(max(progress, 0), 100)
        let durationMs = Int64((runtime * 1000).rounded())
        let positionMs = percent >= finishedPercent ? durationMs : Int64((runtime * percent * 10).rounded())
        let lastWatched = Int64((now.timeIntervalSince1970 * 1000).rounded())

        switch item.kind {
        case .movie, .video:
            guard let id = contentID(from: item.providerIDs, imdbKey: "imdb", tmdbKey: "tmdb") else { return nil }
            return NuvioProgressEntry(
                contentID: id, contentType: "movie", videoID: id,
                season: nil, episode: nil,
                position: positionMs, duration: durationMs,
                lastWatched: lastWatched, progressKey: id
            )
        case .episode:
            guard let season = item.seasonNumber, let episode = item.episodeNumber,
                  let id = contentID(from: item.providerIDs, imdbKey: "seriesimdb", tmdbKey: "seriestmdb")
            else { return nil }
            return NuvioProgressEntry(
                contentID: id, contentType: "series", videoID: "\(id):\(season):\(episode)",
                season: season, episode: episode,
                position: positionMs, duration: durationMs,
                lastWatched: lastWatched, progressKey: "\(id)_s\(season)e\(episode)"
            )
        default:
            return nil
        }
    }

    private static func contentID(from providerIDs: [String: String], imdbKey: String, tmdbKey: String) -> String? {
        var lowered: [String: String] = [:]
        for (key, value) in providerIDs {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lowered[key.lowercased()] = trimmed }
        }
        if let imdb = lowered[imdbKey], imdb.hasPrefix("tt") { return imdb }
        if let tmdb = lowered[tmdbKey], Int(tmdb) != nil { return "tmdb:\(tmdb)" }
        return nil
    }
}
