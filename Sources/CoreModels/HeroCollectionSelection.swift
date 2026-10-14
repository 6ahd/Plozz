import Foundation

/// A provider-local collection, qualified by the profile's account and library.
public struct HeroCollectionSelection: Codable, Hashable, Sendable {
    public let accountID: String
    public let libraryID: String
    public let collectionID: String
    public let serverUserID: String?
    public let title: String // l10n:content — collection name from the server

    public var libraryKey: String { "\(accountID):\(libraryID)" }

    public init(
        accountID: String, libraryID: String, collectionID: String, title: String,
        serverUserID: String? = nil
    ) {
        self.accountID = accountID
        self.libraryID = libraryID
        self.collectionID = collectionID
        self.serverUserID = serverUserID
        self.title = title
    }

    public func matches(_ account: ResolvedAccount) -> Bool {
        accountID == account.account.id
            && (serverUserID == nil || serverUserID == (account.plexHomeUserID ?? account.provider.session.userID))
    }
}
