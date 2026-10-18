import AetherEngine
import CoreModels
import FeaturePlayback
import Foundation

enum PlozzigenPlaybackFailure {
    static func classify(
        _ info: PlaybackErrorInfo?, fallbackError: Error? = nil
    ) -> StreamingPlaybackFailure? {
        let httpStatus = info.flatMap {
            ($0.kind == .sourceRefused || $0.kind == .sourceRateLimited)
                && $0.underlyingDomain == nil ? $0.underlyingCode : nil
        }
        let underlying = info.flatMap { info -> NSError? in
            guard let domain = info.underlyingDomain, let code = info.underlyingCode else { return nil }
            return NSError(domain: domain, code: code)
        } ?? (fallbackError as NSError?)
        let classified = NativePlaybackFailure.classify(underlying, httpStatus: httpStatus)
        if info?.kind == .sourceRateLimited {
            return .init(kind: .rateLimited, httpStatus: classified.httpStatus)
        }
        if classified.kind != .unknown { return classified }
        guard let info else { return nil }
        let kind: StreamingPlaybackFailure.Kind
        switch info.kind {
        case .storageExhausted: kind = .storageExhausted
        case .audioSessionFailed: kind = .audioOutputFailed
        case .dolbyVisionRequiresHardware, .softwarePipelineFailed,
             .audioBridgeProducedNoOutput, .demuxedAudioLiveUnsupported:
            kind = .unsupportedFormat
        case .noPlayableTrackWithinBudget, .liveReloadNeverReady: kind = .timedOut
        case .sourceCertificateRejected, .liveSourceUnavailable: kind = .network
        default: kind = .unknown
        }
        return .init(kind: kind, domain: classified.domain, code: classified.code, httpStatus: classified.httpStatus)
    }
}
