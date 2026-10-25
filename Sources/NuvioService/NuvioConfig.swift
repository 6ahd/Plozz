import Foundation

/// Configuration for the optional Nuvio watch-progress sync.
///
/// Nuvio's account backend is a Supabase project at `api.nuvio.tv`. Every call
/// carries its public anon key (the same key Nuvio's own apps ship); what a
/// signed-in user may read or write is decided by the backend's row-level
/// security, not by the key. It is read from Info.plist (`NuvioAnonKey`,
/// substituted from the gitignored `Config/Secrets.local.xcconfig`), falling back
/// to the process environment. Empty means the integration is unavailable.
public struct NuvioConfig: Sendable, Equatable {
    public var anonKey: String?
    public var apiBaseURL: URL
    /// The page the TV-login QR points at; Nuvio approves the code there.
    public var loginPageURL: URL

    public init(
        anonKey: String? = nil,
        apiBaseURL: URL = URL(string: "https://api.nuvio.tv")!,
        loginPageURL: URL = URL(string: "https://nuvio.tv/tv-login")!
    ) {
        self.anonKey = Self.sanitize(anonKey)
        self.apiBaseURL = apiBaseURL
        self.loginPageURL = loginPageURL
    }

    public var isConfigured: Bool { anonKey != nil }

    public static func resolved(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NuvioConfig {
        let plistKey = bundle.object(forInfoDictionaryKey: "NuvioAnonKey") as? String
        return NuvioConfig(anonKey: sanitize(plistKey) ?? sanitize(environment["NUVIO_ANON_KEY"]))
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.contains("$(")
        else { return nil }
        return trimmed
    }
}
