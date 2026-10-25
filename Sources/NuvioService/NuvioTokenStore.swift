import Foundation
import CoreSecureStore

/// Persists the Nuvio session, namespaced per Plozz profile.
///
/// Unlike the other trackers this store is device-local, not iCloud-synced:
/// Supabase rotates the refresh token on every use and revokes a session whose
/// old refresh token is replayed, so two devices sharing one copy would sign
/// each other out. Each device links Nuvio on its own.
public protocol NuvioTokenStoring: Sendable {
    func load() -> NuvioTokens?
    func save(_ tokens: NuvioTokens) throws
    func clear() throws
    func setNamespace(_ namespace: String?)
}

#if canImport(Security)
public final class KeychainNuvioTokenStore: NuvioTokenStoring, @unchecked Sendable {
    private let store: KeychainStore
    private let baseAccount: String
    private let lock = NSLock()
    private var namespace: String?

    public init(
        service: String = "com.plozz.app.tokens",
        account: String = "nuvio.session",
        namespace: String? = nil
    ) {
        self.store = KeychainStore(service: service)
        self.baseAccount = account
        self.namespace = namespace
    }

    public func setNamespace(_ namespace: String?) {
        lock.lock(); defer { lock.unlock() }
        self.namespace = namespace
    }

    private var account: String {
        lock.lock(); defer { lock.unlock() }
        if let namespace, !namespace.isEmpty { return "\(baseAccount).\(namespace)" }
        return baseAccount
    }

    public func load() -> NuvioTokens? {
        guard let raw = store.string(for: account), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NuvioTokens.self, from: data)
    }

    public func save(_ tokens: NuvioTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try store.setString(String(decoding: data, as: UTF8.self), for: account)
    }

    public func clear() throws {
        try store.removeValue(for: account)
    }
}
#endif

/// In-memory token store for tests/previews.
public final class InMemoryNuvioTokenStore: NuvioTokenStoring, @unchecked Sendable {
    private var storage: [String: NuvioTokens] = [:]
    private var namespace: String?
    private let lock = NSLock()

    public init(tokens: NuvioTokens? = nil) {
        if let tokens { storage[""] = tokens }
    }

    public func setNamespace(_ namespace: String?) {
        lock.lock(); defer { lock.unlock() }
        self.namespace = namespace
    }

    public func load() -> NuvioTokens? {
        lock.lock(); defer { lock.unlock() }
        return storage[namespace ?? ""]
    }

    public func save(_ tokens: NuvioTokens) throws {
        lock.lock(); defer { lock.unlock() }
        storage[namespace ?? ""] = tokens
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        storage[namespace ?? ""] = nil
    }
}
