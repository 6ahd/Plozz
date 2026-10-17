import CoreModels
import Foundation
import MediaTransportCore
import MediaTransportHTTP

/// A random-access byte source over WebDAV/HTTP `Range` reads.
///
/// Every read is a bounded `Range` GET gated on the probe's strong ETag
/// (`If-Match`) or Last-Modified (`If-Unmodified-Since`). Changed or missing
/// validators fail closed; date-based detection has one-second precision.
/// The delivery URL and validator remain fixed for this lease, even on expiry.
/// Reads are stateless (no server-side cursor/handle), so —
/// unlike SMB's channel-per-cursor source — no per-cursor isolation is needed:
/// a cancelled read cancels only its own `URLSessionTask`, and the owning
/// ``WebDAVMediaTransportSession`` drains the shared ephemeral session on
/// shutdown.
final class WebDAVByteSource: MediaTransportByteSource, @unchecked Sendable {
    let byteSize: Int64
    let preferredReadSize = 32 * 1024 * 1024

    private let client: WebDAVClient
    private let resourceURL: URL
    private let representation: RangeProbeResult
    private let sessionKey: TransportSessionKey
    private let credential: WebDAVCredential
    private let trustPolicy: TrustPolicy

    init(
        client: WebDAVClient,
        representation: RangeProbeResult,
        sessionKey: TransportSessionKey,
        credential: WebDAVCredential,
        trustPolicy: TrustPolicy
    ) {
        self.client = client
        self.resourceURL = representation.resourceURL
        self.representation = representation
        self.sessionKey = sessionKey
        self.credential = credential
        self.trustPolicy = trustPolicy
        self.byteSize = representation.totalLength
    }

    func read(at offset: Int64, length: Int) async throws -> Data {
        guard offset >= 0, length > 0 else {
            throw MediaTransportError.invalidInput(reason: "invalid WebDAV byte range")
        }
        // Reads at or past EOF are a normal end-of-stream signal (AVIO probes
        // past the end), not an error — return empty rather than asking the
        // server for an unsatisfiable range (which would be a 416).
        guard offset < byteSize else {
            return Data()
        }
        let lastByte = byteSize - 1
        let requestedEnd = offset.addingReportingOverflow(Int64(length) - 1)
        let end = requestedEnd.overflow ? lastByte : min(requestedEnd.partialValue, lastByte)

        do {
            let count = end - offset + 1
            let halfWindow: Int64 = 16 * 1024 * 1024
            guard count > halfWindow, count <= Int64(preferredReadSize) else {
                return try await readRange(start: offset, end: end)
            }
            // Overlap only the current window, never speculative bytes. Each half
            // must independently pass the pinned representation/range checks.
            async let first = readRange(start: offset, end: offset + halfWindow - 1)
            async let second = readRange(start: offset + halfWindow, end: end)
            var bytes = try await first
            bytes.append(try await second)
            try Task.checkCancellation()
            return bytes
        } catch {
            throw mapWebDAVError(error)
        }
    }

    private func readRange(start: Int64, end: Int64) async throws -> Data {
        try await client.readRange(
            url: resourceURL, start: start, end: end, representation: representation,
            sessionKey: sessionKey, credential: credential, trustPolicy: trustPolicy
        )
    }

    func shutdown() async {
        // No per-source resource to release: the ephemeral URLSession backing
        // these reads is owned by the transport session's registry and drained
        // when that session shuts down. Deterministic teardown is therefore the
        // session's responsibility; a cancelled in-flight read is torn down at
        // the URLSessionTask level by structured cancellation.
    }
}
