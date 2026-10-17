#if canImport(AetherEngine)
import Foundation
import XCTest
@testable import EnginePlozzigen
@testable import TestSupportPerformance

private final class LatencyByteSource: TransportByteSource, @unchecked Sendable {
    let byteSize: Int64 = 512 * 1024 * 1024
    let preferredReadSize = 32 * 1024 * 1024
    private let lock = NSLock()
    private var reads = 0
    private var bytes = 0
    private var largest = 0

    var counters: [String: Int] {
        lock.withLock {
            ["transportReads": reads, "transportBytes": bytes, "largestRequest": largest]
        }
    }

    func read(at offset: Int64, length: Int) async throws -> Data {
        try await Task.sleep(for: .milliseconds(5))
        let count = min(length, Int(byteSize - offset))
        lock.withLock {
            reads += 1
            bytes += count
            largest = max(largest, length)
        }
        return Data(repeating: 0x5a, count: count)
    }

    func shutdown() async {}
}

@MainActor
final class TransportReadAheadPerformanceTests: XCTestCase {
    func testPerformanceRepeatedDiscMetadataProbes() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "disc-probe-cache") {
            let source = LatencyByteSource()
            let reader = TransportIOReader(source: source)
            let completed = await Task.detached {
                let offsets = [32, 512, 64, 576, 704, 896, 706, 898, 708, 930, 710,
                               932, 712, 934, 714, 936, 580, 716, 580, 676, 828]
                var buffer = [UInt8](repeating: 0, count: 2048)
                var completed = 0
                for offsetKiB in offsets {
                    let offset = Int64(offsetKiB * 1024)
                    XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
                    let count = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: Int32($0.count))
                    }
                    XCTAssertEqual(count, 2048)
                    XCTAssertTrue(buffer.allSatisfy { $0 == 0x5a })
                    completed += 1
                }
                return completed
            }.value
            reader.close()
            await reader.waitForFinalShutdown()
            XCTAssertEqual(completed, 21)
            return source.counters.merging(["metadataReads": completed]) { _, new in new }
        }
    }

    func testPerformanceRandomAndSequentialReads() async throws {
        try PerformanceProbe.requireEnabled()
        try await PerformanceProbe.measure(self, scenario: "network-file-read-ahead") {
            let source = LatencyByteSource()
            let reader = TransportIOReader(source: source)
            let completed = await Task.detached {
                var buffer = [UInt8](repeating: 0, count: 256 * 1024)
                var metadataReads = 0
                let offsets: [Int64] = [32_768, 128 * 1024 * 1024, 64 * 1024 * 1024, 384 * 1024 * 1024]
                for offset in offsets {
                    XCTAssertEqual(reader.seek(offset: offset, whence: SEEK_SET), offset)
                    let read = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: 2048)
                    }
                    XCTAssertEqual(read, 2048)
                    XCTAssertTrue(buffer.prefix(2048).allSatisfy { $0 == 0x5a })
                    metadataReads += 1
                }
                XCTAssertEqual(reader.seek(offset: 256 * 1024 * 1024, whence: SEEK_SET), 256 * 1024 * 1024)
                var consumed = 0
                while consumed < 64 * 1024 * 1024 {
                    let length = min(buffer.count, 64 * 1024 * 1024 - consumed)
                    let read = buffer.withUnsafeMutableBufferPointer {
                        reader.read($0.baseAddress, size: Int32(length))
                    }
                    guard read > 0 else {
                        XCTFail("The complete sequential workload must be delivered")
                        break
                    }
                    XCTAssertTrue(buffer.prefix(Int(read)).allSatisfy { $0 == 0x5a })
                    consumed += Int(read)
                }
                return (metadataReads, consumed)
            }.value
            reader.close()
            await reader.waitForFinalShutdown()
            XCTAssertEqual(completed.0, 4)
            XCTAssertEqual(completed.1, 64 * 1024 * 1024)
            return source.counters.merging([
                "metadataReads": completed.0, "consumedBytes": completed.1
            ]) { _, new in new }
        }
    }
}
#endif
