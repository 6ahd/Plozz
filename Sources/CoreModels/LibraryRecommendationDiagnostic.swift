import Foundation

/// Only allowlisted response facts may enter a user-shared library report.
public struct ResponseDecodingDiagnostic: Equatable, Sendable {
    public enum Route: String, Sendable {
        case movieRecommendations, libraryHubs, other
    }
    public enum Payload: String, Sendable { case empty, object, array, scalar, nonJSON }
    public enum Reason: String, Sendable { case missingKey, wrongType, nullValue, corruptedData, other }
    public enum ValueType: String, Sendable { case string, integer, number, boolean, array, object, other }

    public let route: Route
    public let httpStatus: Int
    public let bytes: Int
    public let payload: Payload
    public let reason: Reason
    public let expected: ValueType?
    public let path: String

    public init(route: Route, httpStatus: Int, bytes: Int, payload: Payload, error: Error) {
        self.route = route
        self.httpStatus = httpStatus
        self.bytes = bytes
        self.payload = payload
        let keys: [CodingKey]
        switch error {
        case let DecodingError.keyNotFound(key, context):
            reason = .missingKey
            expected = nil
            keys = context.codingPath + [key]
        case let DecodingError.typeMismatch(type, context):
            reason = .wrongType
            expected = Self.valueType(type)
            keys = context.codingPath
        case let DecodingError.valueNotFound(type, context):
            reason = .nullValue
            expected = Self.valueType(type)
            keys = context.codingPath
        case let DecodingError.dataCorrupted(context):
            reason = .corruptedData
            expected = nil
            keys = context.codingPath
        default:
            reason = .other
            expected = nil
            keys = []
        }
        // Dynamic dictionary keys and decoder descriptions can contain credentials.
        let fields: Set<String> = [
            "Items", "Id", "Name", "Type", "RecommendationType", "CategoryId", "BaselineItemName",
            "TotalRecordCount", "UserData", "MediaSources", "MediaStreams", "ProviderIds",
            "RunTimeTicks", "Size", "IndexNumber", "ParentIndexNumber", "ProductionYear",
            "MediaContainer", "Metadata", "Hub", "Directory", "ratingKey", "key", "type",
            "title", "size", "totalSize", "offset", "viewOffset", "duration"
        ]
        path = keys.isEmpty ? "<root>" : keys.prefix(24).map {
            if let index = $0.intValue, $0.stringValue == "Index \(index)" { return "[\(index)]" }
            return fields.contains($0.stringValue) ? $0.stringValue : "<field>"
        }.joined(separator: ".")
    }

    private static func valueType(_ type: Any.Type) -> ValueType {
        if type == String.self { return .string }
        if type == Bool.self { return .boolean }
        if type == Int.self || type == Int64.self || type == Int32.self
            || type == UInt.self || type == UInt64.self { return .integer }
        if type == Double.self || type == Float.self { return .number }
        if String(describing: type).hasPrefix("Array<") { return .array }
        if String(describing: type).hasPrefix("Dictionary<") { return .object }
        return .other
    }
}

public struct LibraryRecommendationDiagnostic: Equatable, Sendable {
    public enum Section: String, Sendable {
        case continueWatching, recommendations, recentlyAdded

        public var title: LocalizedStringResource {
            switch self {
            case .continueWatching: "Continue Watching"
            case .recommendations: "Recommended"
            case .recentlyAdded: "Recently Added"
            }
        }
    }

    public struct Failure: Equatable, Sendable {
        public let section: Section
        public let error: AppError
        public let responses: [ResponseDecodingDiagnostic]

        public init(section: Section, error: AppError, responses: [ResponseDecodingDiagnostic] = []) {
            self.section = section
            self.error = error
            self.responses = Array(responses.suffix(4))
        }
    }

    public let provider: ProviderKind
    public let failures: [Failure]

    public init(provider: ProviderKind, failures: [Failure]) {
        self.provider = provider
        self.failures = failures
    }

    // l10n:content — closed-vocabulary, credential-free support protocol
    public var supportText: String {
        var fields = ["format=plozz-library-1", "operation=libraryRecommendations", "provider=\(provider.rawValue)"]
        for (index, failure) in failures.enumerated() {
            let prefix = "failure_\(index)"
            fields += ["\(prefix).section=\(failure.section.rawValue)", "\(prefix).reason=\(Self.code(failure.error))"]
            for (responseIndex, response) in failure.responses.enumerated() {
                let request = "\(prefix).response_\(responseIndex)"
                fields += [
                    "\(request).route=\(response.route.rawValue)", "\(request).http_status=\(response.httpStatus)",
                    "\(request).bytes=\(response.bytes)", "\(request).payload=\(response.payload.rawValue)",
                    "\(request).decode=\(response.reason.rawValue)", "\(request).path=\(response.path)"
                ]
                if let expected = response.expected { fields.append("\(request).expected=\(expected.rawValue)") }
            }
        }
        return fields.joined(separator: "\n")
    }

    private static func code(_ error: AppError) -> String {
        switch error {
        case .serverUnreachable: "serverUnreachable"
        case .invalidResponse: "invalidResponse"
        case .unauthorized: "unauthorized"
        case .accessRestricted: "accessRestricted"
        case .invalidCredentials: "invalidCredentials"
        case .notFound: "notFound"
        case .conflict: "conflict"
        case .rateLimited: "rateLimited"
        case .quickConnectUnavailable: "quickConnectUnavailable"
        case .quickConnectExpired: "quickConnectExpired"
        case .cancelled: "cancelled"
        case .decoding: "decoding"
        case .unknown: "unknown"
        }
    }
}
