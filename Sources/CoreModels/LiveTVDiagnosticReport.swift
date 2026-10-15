import Foundation

/// A local, user-shared report. Only closed-vocabulary facts are exported.
public enum LiveTVDiagnosticReport: Equatable, Sendable {
    case setup(IPTVSetupDiagnostic)
    case playback(LiveChannelFailureReport)

    public var message: LocalizedStringResource? {
        switch self {
        case .playback(let report): return report.message
        case .setup(let diagnostic):
            guard diagnostic.outcome == .failed, let failure = diagnostic.failure else { return nil }
            if [.storage, .invalidInput, .sourceChanged, .fileUnavailable].contains(failure.reason) { return nil }
            if let message = Self.providerMessage(httpStatus: diagnostic.httpStatus, networkCode: failure.networkCode) {
                return message
            }
            if diagnostic.response == .html, [.malformed, .invalidResponse, .empty].contains(failure.reason) {
                return "The provider returned HTML instead of a playlist or channel list. Check the address; it may lead to a login or error page."
            }
            return nil
        }
    }

    // l10n:content — stable, credential-free support protocol fields, not UI labels
    public var supportText: String {
        var fields = ["format=plozz-live-tv-1"]
        func field(_ key: String, _ value: String?) {
            if let value { fields.append("\(key)=\(value)") }
        }
        func number(_ key: String, _ value: Int?) { field(key, value.map(String.init)) }
        switch self {
        case .setup(let diagnostic):
            field("operation", "setup")
            field("source", diagnostic.source.rawValue)
            field("authentication", diagnostic.authentication.rawValue)
            field("entry", diagnostic.entry.rawValue)
            field("stage", diagnostic.stage.rawValue)
            field("outcome", diagnostic.outcome.rawValue)
            field("reason", diagnostic.failure?.reason.rawValue)
            field("response", diagnostic.response?.rawValue)
            number("http_status", diagnostic.httpStatus)
            number("network_code", diagnostic.failure?.networkCode)
            number("sqlite_code", diagnostic.failure?.sqliteCode)
            number("elapsed_ms", diagnostic.elapsedMilliseconds)
            number("stage_ms", diagnostic.stageMilliseconds)
            number("requests", diagnostic.requestCount)
            number("entries", diagnostic.entries)
            number("playlist_bytes", diagnostic.playlistBytes)
            number("skipped_entries", diagnostic.skippedEntries)
        case .playback(let report):
            field("operation", "playback")
            field("failure", report.failure.diagnosticCode)
            if let diagnostic = report.diagnostic {
                field("layer", diagnostic.layer.rawValue)
                field("stage", diagnostic.stage.rawValue)
                field("reason", diagnostic.reason.rawValue)
                field("engine_failure", diagnostic.engineFailure.rawValue)
                field("domain", diagnostic.domain.rawValue)
                field("format", diagnostic.format.rawValue)
                number("code", diagnostic.code)
                number("http_status", diagnostic.httpStatus)
                number("elapsed_ms", diagnostic.elapsedMilliseconds)
            }
        }
        return fields.joined(separator: "\n")
    }

    static func providerMessage(httpStatus: Int?, networkCode: Int?) -> LocalizedStringResource? {
        switch httpStatus {
        case 401:
            return "The provider rejected the login (HTTP 401). Check your account details."
        case 403:
            return "The provider refused access (HTTP 403). Contact your provider to check this account's access."
        case 404, 410:
            return "The provider could not find this playlist or stream. Refresh the source or check the address."
        case 429, 509:
            return "The provider is limiting requests. Wait before trying again."
        case 451:
            return AppError.accessRestricted.userMessage
        case .some(let status) where (500...599).contains(status):
            return "The provider returned a server error (HTTP \(status)). Try again later."
        default: break
        }
        switch networkCode {
        case URLError.timedOut.rawValue:
            return "The provider did not respond in time. Check your connection, then try again."
        case URLError.notConnectedToInternet.rawValue:
            return "Your device is offline. Connect to the internet and try again."
        case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue:
            return "The provider's address could not be found. Check the address and your network's DNS settings."
        case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateHasBadDate.rawValue,
             URLError.serverCertificateUntrusted.rawValue, URLError.serverCertificateHasUnknownRoot.rawValue,
             URLError.serverCertificateNotYetValid.rawValue:
            return "A secure connection to the provider could not be established. Check your device's date and contact your provider."
        default: return nil
        }
    }
}
