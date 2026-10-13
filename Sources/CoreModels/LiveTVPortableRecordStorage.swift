import Foundation
import os

/// Worker-written backing, immutable after publication; never an authoritative sync store.
final class LiveTVPortableRecordStorage: @unchecked Sendable {
    static let maximumResidentBytes = 4 * 1_024 * 1_024
    static let maximumStoredBytes = 128 * 1_024 * 1_024
    private static let logger = Logger(subsystem: "com.plozz.app", category: "live-tv-sync")
    private(set) var residentBytes = 0
    private(set) var storedBytes = 0
    private var directory: URL?
    private var nextFile = 0

    func store(_ bytes: Data) throws -> Data {
        try Task.checkCancellation()
        guard bytes.count <= Self.maximumStoredBytes - storedBytes else {
            throw LiveTVPortableStateError.tooLarge
        }
        storedBytes += bytes.count
        if bytes.count <= Self.maximumResidentBytes - residentBytes {
            residentBytes += bytes.count
            return bytes
        }
        let directory: URL
        if let existing = self.directory {
            directory = existing
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("plozz-live-tv-records-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
            self.directory = directory
        }
        let file = directory.appendingPathComponent("\(nextFile).record")
        nextFile += 1
        try bytes.write(to: file, options: .atomic)
        return try Data(contentsOf: file, options: .alwaysMapped)
    }

    deinit {
        guard let directory else { return }
        DispatchQueue.global(qos: .utility).async {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Self.logger.error("Unable to remove retired Live TV record staging: \(error.localizedDescription, privacy: .private)") }
        }
    }
}
