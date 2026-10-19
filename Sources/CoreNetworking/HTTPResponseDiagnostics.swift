import CoreModels
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Opt-in, task-scoped evidence; the provider's thrown errors and fallback behavior stay unchanged.
public enum HTTPResponseDiagnostics {
    public struct CapturedResult<Value: Sendable>: Sendable {
        public let result: Result<Value, Error>
        public let responses: [ResponseDecodingDiagnostic]

        public var isCancelled: Bool {
            guard case .failure(let error) = result else { return false }
            let underlying = LibrarySourceFailure.underlying(error)
            return underlying is CancellationError || (underlying as? AppError) == .cancelled
        }
    }

    @TaskLocal private static var recorder: Recorder?
    @TaskLocal public static var route: ResponseDecodingDiagnostic.Route = .other

    public static func capture<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> CapturedResult<Value> {
        let recorder = Recorder()
        return await $recorder.withValue(recorder) {
            do {
                return CapturedResult(result: .success(try await operation()), responses: [])
            } catch {
                return CapturedResult(result: .failure(error), responses: recorder.snapshot())
            }
        }
    }

    public static func recordDecodeFailure(
        _ error: Error, data: Data, response: HTTPURLResponse
    ) {
        guard let recorder else { return }
        let payload: ResponseDecodingDiagnostic.Payload
        if data.isEmpty { payload = .empty }
        else if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            payload = json is [Any] ? .array : json is [String: Any] ? .object : .scalar
        } else { payload = .nonJSON }
        recorder.append(ResponseDecodingDiagnostic(
            route: route, httpStatus: response.statusCode, bytes: data.count,
            payload: payload, error: error
        ))
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [ResponseDecodingDiagnostic] = []

        func append(_ response: ResponseDecodingDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            responses.append(response)
            if responses.count > 4 { responses.removeFirst() }
        }

        func snapshot() -> [ResponseDecodingDiagnostic] {
            lock.lock()
            defer { lock.unlock() }
            return responses
        }
    }
}
