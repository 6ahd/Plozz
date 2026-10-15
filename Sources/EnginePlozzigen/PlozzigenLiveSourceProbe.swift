import CoreModels
import Foundation

/// Opaque IPTV addresses describe a resource, not its container. Inspect a small
/// prefix before choosing AVPlayer's HLS bypass or the engine's demuxer.
final class PlozzigenLiveSourceProbe: Sendable {
    enum Format: Equatable, Sendable {
        case hls, transportStream, other
    }

    private let session: URLSession
    static let maximumBytes = 1_024

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }
    func cancel() { session.invalidateAndCancel() }

    static func isRequired(for url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && !["m3u8", "ts", "m2ts", "mts"].contains(url.pathExtension.lowercased())
    }

    func format(url: URL, headers: [String: String]) async throws -> Format {
        try Task.checkCancellation()
        guard LiveTVPlaylistSource.isSupportedURL(url) else { throw AppError.invalidResponse }
        try IPTVCredential.validate(headers: headers)
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        // A live origin may legitimately ignore Range. No seek support is needed
        // to identify a prefix, and an endless response must never be downloaded.
        return try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request, delegate: Redirects())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw AppError.invalidResponse }
            try Self.validate(response)
            var prefix = Data()
            prefix.reserveCapacity(Self.maximumBytes)
            return try await withTaskCancellationHandler {
                for try await byte in bytes {
                    try Task.checkCancellation()
                    prefix.append(byte)
                    if let format = Self.recognizedFormat(prefix) { return format }
                    if prefix.count == Self.maximumBytes { break }
                }
                guard !prefix.isEmpty else { throw AppError.invalidResponse }
                // Unknown non-playlist data belongs to the real container probe,
                // not a guess that an extensionless address must be HLS.
                return .other
            } onCancel: {
                bytes.task.cancel()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    static func recognizedFormat(_ prefix: Data) -> Format? {
        let text = String(decoding: prefix.prefix(256), as: UTF8.self)
            .drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
        if text.utf8.starts(with: "#EXTM3U".utf8),
           let lineBreak = text.utf8.dropFirst(7).first, lineBreak == 10 || lineBreak == 13 {
            return .hls
        }
        let bytes = [UInt8](prefix)
        for (stride, offset) in [(188, 0), (192, 4), (204, 0)] {
            if bytes.count > offset + stride * 2,
               bytes[offset] == 0x47, bytes[offset + stride] == 0x47,
               bytes[offset + stride * 2] == 0x47 {
                return .transportStream
            }
        }
        return nil
    }

    private static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw AppError.unauthorized
        case 404, 410: throw AppError.notFound
        case 451: throw AppError.accessRestricted
        case 429, 503, 509:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AppError.rateLimited(retryAfter: delay.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
        default: throw AppError.invalidResponse
        }
    }

    private final class Redirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(PlozzigenLiveSourceProbe.redirect(
                request, previous: response.url, original: task.originalRequest?.url
            ))
        }
    }

    static func redirect(_ request: URLRequest, previous: URL?, original: URL?) -> URLRequest? {
        guard let next = request.url, let previous, let original,
              LiveTVPlaylistSource.isSupportedURL(next) else { return nil }
        if IPTVCredential.sameOrigin(previous, next), IPTVCredential.sameOrigin(original, next) {
            return request
        }
        // Match IPTV delivery: follow provider-issued destinations, but never
        // forward the original account's headers to a different origin.
        var clean = URLRequest(url: next)
        clean.timeoutInterval = request.timeoutInterval
        clean.httpMethod = "GET"
        clean.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return clean
    }
}
