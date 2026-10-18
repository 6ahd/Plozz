import Foundation

public enum LiveChannelPlaybackFailure: Equatable, Sendable {
    case startupTimedOut
    case bufferingTimedOut
    case recoveryExhausted
    case engine(AppError)
    case input(LiveChannelInputError)
    case library(LibraryChannelError)
    case ended
    case initializationFailed

    public var message: LocalizedStringResource {
        switch self {
        case .startupTimedOut: "The channel did not start in time. Check your connection, then retry or choose another channel."
        case .bufferingTimedOut: "The channel stopped delivering playable video. Check your connection, then retry or choose another channel."
        case .recoveryExhausted: "This channel keeps disconnecting. Try again or choose another channel."
        case .engine(let error): Self.engineMessage(error)
        case .input(let error): error.message
        case .library(let error): error.message
        case .ended: "The channel’s stream ended. Retry or choose another channel."
        case .initializationFailed: "The player could not be started. Close playback and try again."
        }
    }

    public static func engineMessage(_ error: AppError) -> LocalizedStringResource {
        switch error {
        case .notFound:
            "The channel provider could not find this stream. Its playlist link may be outdated, or the feed may be temporarily off air."
        case .unauthorized, .invalidCredentials:
            "The channel provider refused access to this stream. Check your account details or contact your provider."
        case .accessRestricted:
            error.userMessage
        case .serverUnreachable:
            "Plozz could not reach the channel's streaming server. Check your internet connection or try again later."
        case .rateLimited:
            "The channel provider is limiting requests. Wait before trying again."
        case .invalidResponse:
            "The channel's playlist or video data could not be opened. Its link may be outdated or the feed may be temporarily unavailable."
        case .decoding:
            "The player could not decode this channel's audio or video. Try another stream version or channel."
        case .cancelled:
            "Opening this channel was cancelled."
        default:
            "Plozz could not start playback. Retry or choose another channel."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .startupTimedOut: "startupTimedOut"
        case .bufferingTimedOut: "bufferingTimedOut"
        case .recoveryExhausted: "recoveryExhausted"
        case .input: "unsupportedSource"
        case .library: "library"
        case .ended: "ended"
        case .initializationFailed: "initializationFailed"
        case .engine(let error):
            switch error {
            case .serverUnreachable: "serverUnreachable"
            case .invalidResponse: "invalidResponse"
            case .unauthorized: "unauthorized"
            case .invalidCredentials: "invalidCredentials"
            case .accessRestricted: "accessRestricted"
            case .notFound: "notFound"
            case .rateLimited: "rateLimited"
            case .decoding: "decoding"
            case .cancelled: "cancelled"
            default: "unknown"
            }
        }
    }
}

/// Captured before stopping the engine, then retained by the presenting guide.
public struct LiveChannelFailureReport: Equatable, Sendable {
    public let failure: LiveChannelPlaybackFailure
    public let diagnostic: PlaybackFailureDiagnostic?

    public init(failure: LiveChannelPlaybackFailure, diagnostic: PlaybackFailureDiagnostic? = nil) {
        self.failure = failure
        self.diagnostic = diagnostic
    }

    public var message: LocalizedStringResource {
        switch failure {
        case .engine:
            LiveTVDiagnosticReport.providerMessage(
                httpStatus: diagnostic?.httpStatus,
                networkCode: diagnostic?.domain == .url ? diagnostic?.code : nil
            ) ?? failure.message
        default: failure.message
        }
    }
}
