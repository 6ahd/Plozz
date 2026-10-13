import CryptoKit
import Foundation

public protocol HomeLiveTVSnapshotStoring: Sendable {
    func load() -> HomeLiveTVSnapshot
    func save(_ snapshot: HomeLiveTVSnapshot)
}

/// A local, disposable cache of at most eleven cards, separate from preferences,
/// the encrypted lineup and portable sync. Reads are capped before JSON decoding.
public final class HomeLiveTVSnapshotStore: HomeLiveTVSnapshotStoring, @unchecked Sendable {
    public static let maximumBytes = 64 * 1_024
    private let profileID: String
    private let url: URL?
    private let lock = NSLock()

    private struct Document: Codable {
        var version = 1
        let profileID: String
        let recentChannels: [HomeLiveTVChannel]
        let channels: [HomeLiveTVChannel]
    }

    public init(profileID: String, directory: URL? = HomeLiveTVSnapshotStore.defaultDirectory()) {
        self.profileID = profileID
        let name = SHA256.hash(data: Data(profileID.utf8)).map { String(format: "%02x", $0) }.joined()
        url = directory?.appendingPathComponent(name).appendingPathExtension("json")
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Plozz/HomeLiveTV-v1", isDirectory: true)
    }

    public func load() -> HomeLiveTVSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let url, let handle = try? FileHandle(forReadingFrom: url) else { return .empty }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumBytes + 1),
              data.count <= Self.maximumBytes,
              let document = try? JSONDecoder().decode(Document.self, from: data),
              isValid(document) else { return .empty }
        return HomeLiveTVSnapshot(recentChannels: document.recentChannels, channels: document.channels)
    }

    public func save(_ snapshot: HomeLiveTVSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let url else { return }
        if snapshot.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let document = Document(
            profileID: profileID, recentChannels: snapshot.recentChannels, channels: snapshot.channels
        )
        guard isValid(document), let data = try? JSONEncoder().encode(document),
              data.count <= Self.maximumBytes else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache write never changes the current session's live authority.
        }
    }

    private func isValid(_ document: Document) -> Bool {
        guard document.version == 1, document.profileID == profileID,
              document.recentChannels.count <= HomeLiveTVSnapshot.maximumRecentCount,
              document.channels.count <= HomeLiveTVSnapshot.maximumRowCount,
              Set(document.recentChannels.map(\.id)).count == document.recentChannels.count,
              Set(document.channels.map(\.id)).count == document.channels.count else { return false }
        let cards = document.recentChannels + document.channels
        guard Set(cards.map(\.route.sourceAuthorizationID)).count <= 1,
              Set(cards.map(\.route.serverAuthorizationID)).count <= 1 else { return false }
        return cards.allSatisfy { card in
            let route = card.route
            return route.profileID == profileID
                && !route.profileID.isEmpty && route.profileID.utf8.count <= 256
                && !route.channelID.isEmpty && route.channelID.utf8.count <= 1_024
                && !route.sourceID.isEmpty && route.sourceID.utf8.count <= 256
                && (route.accountID.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
                && !route.sourceAuthorizationID.isEmpty && route.sourceAuthorizationID.utf8.count <= 1_024
                && !route.serverAuthorizationID.isEmpty && route.serverAuthorizationID.utf8.count <= 8_192
                && !card.name.isEmpty && card.name.count <= 160 && card.name.utf8.count <= 1_024
                && card.sourceName.count <= 160 && card.sourceName.utf8.count <= 1_024
        }
    }
}
