import CommonCrypto
import XCTest

@testable import EnginePlozzigen

final class HLSSampleDecryptionTests: XCTestCase {
    private let key = Data((0..<16).map { UInt8($0 &* 7 &+ 3) })
    private let iv = Data((0..<16).map { UInt8(0xF0 &- $0) })

    /// Encrypts `ranges` of `bytes` as one chained run, as a packager would.
    private func encrypt(_ bytes: [UInt8], ranges: [Range<Int>], mode: Int) -> [UInt8] {
        var output = bytes
        var ref: CCCryptorRef?
        key.withUnsafeBytes { k in
            iv.withUnsafeBytes { v in
                _ = CCCryptorCreateWithMode(
                    CCOperation(kCCEncrypt), CCMode(mode), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                    v.baseAddress, k.baseAddress, 16, nil, 0, 0,
                    CCModeOptions(mode == kCCModeCTR ? kCCModeOptionCTR_BE : 0), &ref
                )
            }
        }
        defer { CCCryptorRelease(ref) }
        for range in ranges {
            var out = [UInt8](repeating: 0, count: range.count)
            var moved = 0
            _ = output.withUnsafeBufferPointer {
                CCCryptorUpdate(ref, $0.baseAddress! + range.lowerBound, range.count, &out, out.count, &moved)
            }
            output.replaceSubrange(range, with: out)
        }
        return output
    }

    private func pattern(_ bytes: [UInt8]) -> [UInt8] { bytes.indices.map { UInt8(($0 * 31 + 5) & 0xFF) } }

    func testEmulationPreventionRoundTrips() {
        let raw: [UInt8] = [0x65, 0, 0, 1, 0, 0, 0, 7, 0, 0, 3, 9]
        let escaped = HLSSampleDecryption.escape(raw)
        XCTAssertFalse(escaped.windows(ofCount: 3).contains { $0.elementsEqual([0, 0, 1]) })
        XCTAssertEqual(HLSSampleDecryption.unescape(escaped), raw)
    }

    func testSampleAESNALDecryptsApplesPattern() {
        var plain = pattern([UInt8](repeating: 0, count: 400))
        plain[0] = 0x65
        // 32 clear bytes, then one block in ten, chained; a last block of 16 or fewer stays clear.
        var ranges: [Range<Int>] = []
        var offset = 32
        var remaining = plain.count - 32
        while remaining > 0 {
            if remaining > 16 { ranges.append(offset..<(offset + 16)); offset += 16; remaining -= 16 }
            let skip = min(144, remaining); offset += skip; remaining -= skip
        }
        var encrypted = encrypt(plain, ranges: ranges, mode: kCCModeCBC)
        XCTAssertNotEqual(encrypted, plain)
        HLSSampleDecryption.decryptSampleAESNAL(&encrypted, key: key, iv: iv)
        XCTAssertEqual(encrypted, plain)
    }

    func testCBCSSubsamplesRestartTheIVAndFollowThePattern() {
        let plain = pattern([UInt8](repeating: 0, count: 700))
        let track = HLSSampleDecryption.TrackEncryption(
            scheme: .cbcs, trackID: 1, cryptBlocks: 1, skipBlocks: 9, perSampleIVSize: 0, constantIV: iv
        )
        let subsamples = [(clear: 20, protected: 300), (clear: 10, protected: 370)]
        var encrypted = plain
        var cursor = 0
        for entry in subsamples {
            let start = cursor + entry.clear
            var ranges: [Range<Int>] = []
            var offset = start
            while offset + 16 <= start + entry.protected { ranges.append(offset..<(offset + 16)); offset += 160 }
            encrypted = encrypt(encrypted, ranges: ranges, mode: kCCModeCBC)
            cursor = start + entry.protected
        }
        XCTAssertNotEqual(encrypted, plain)
        HLSSampleDecryption.decryptSample(&encrypted, 0..<700, subsamples: subsamples, track: track, key: key, iv: iv)
        XCTAssertEqual(encrypted, plain)
    }

    func testCENCCounterRunsThroughASamplesProtectedBytes() {
        let plain = pattern([UInt8](repeating: 0, count: 300))
        let track = HLSSampleDecryption.TrackEncryption(
            scheme: .cenc, trackID: 1, cryptBlocks: 0, skipBlocks: 0, perSampleIVSize: 16, constantIV: nil
        )
        let subsamples = [(clear: 10, protected: 90), (clear: 5, protected: 195)]
        let encrypted = encrypt(plain, ranges: [10..<100, 105..<300], mode: kCCModeCTR)
        var bytes = encrypted
        HLSSampleDecryption.decryptSample(&bytes, 0..<300, subsamples: subsamples, track: track, key: key, iv: iv)
        XCTAssertEqual(bytes, plain)
    }

    func testPlaylistKeysAndSequences() throws {
        let base = try XCTUnwrap(URL(string: "https://cdn.test/live/index.m3u8"))
        let text = """
        #EXTM3U
        #EXT-X-MEDIA-SEQUENCE:41
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="key.bin",IV=0x000102030405060708090A0B0C0D0E0F,KEYFORMAT="identity"
        #EXTINF:6.0,
        a.ts
        #EXT-X-KEY:METHOD=NONE
        #EXTINF:6.0,
        b.ts
        """
        let playlist = try XCTUnwrap(LiveHLSScrubThumbnails.parseMediaPlaylist(text, base: base))
        XCTAssertEqual(playlist.segments.map(\.sequence), [41, 42])
        let key = try XCTUnwrap(playlist.segments[0].key)
        XCTAssertEqual(key.method, "SAMPLE-AES")
        XCTAssertEqual(key.url?.absoluteString, "https://cdn.test/live/key.bin")
        XCTAssertEqual(key.iv?.count, 16)
        XCTAssertNil(playlist.segments[1].key)
        XCTAssertTrue(LiveHLSScrubThumbnails.canDecrypt(key, fragmented: false))
        let fairPlay = LiveHLSScrubThumbnails.Key(
            method: "SAMPLE-AES", url: URL(string: "skd://x"), iv: nil, keyFormat: "com.apple.streamingkeydelivery"
        )
        XCTAssertFalse(LiveHLSScrubThumbnails.canDecrypt(fairPlay, fragmented: true))
        XCTAssertEqual(LiveHLSScrubThumbnails.sequenceIV(258).suffix(2), Data([1, 2]))
    }
}

final class LiveHLSThumbnailVariantTests: XCTestCase {
    private let base = URL(string: "https://cdn.test/live/master.m3u8")!

    func testPicksTheSmallestVideoVariantAtLeast640Wide() {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
        audio.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=416x234,CODECS="avc1.42c01e,mp4a.40.2"
        234.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        1080.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2"
        360.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=960x540,CODECS="avc1.4d401f,mp4a.40.2"
        540.m3u8
        """
        XCTAssertEqual(LiveHLSScrubThumbnails.thumbnailVariant(in: master, base: base)?.lastPathComponent, "360.m3u8")
    }

    func testFallsBackToTheWidestBelow640ThenTheLowestBandwidth() {
        let small = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=320x180
        180.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=480x270
        270.m3u8
        """
        XCTAssertEqual(LiveHLSScrubThumbnails.thumbnailVariant(in: small, base: base)?.lastPathComponent, "270.m3u8")
        let unsized = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000
        hi.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        lo.m3u8
        """
        XCTAssertEqual(LiveHLSScrubThumbnails.thumbnailVariant(in: unsized, base: base)?.lastPathComponent, "lo.m3u8")
        XCTAssertNil(LiveHLSScrubThumbnails.thumbnailVariant(in: "#EXTM3U\n#EXTINF:6,\na.ts", base: base))
    }
}

private extension Array {
    func windows(ofCount count: Int) -> [ArraySlice<Element>] {
        guard self.count >= count else { return [] }
        return (0...(self.count - count)).map { self[$0..<($0 + count)] }
    }
}
