#if os(iOS)
import CoreModels
import CoreImage
import CoreUI
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import AppShelliOS

@MainActor
final class VersionPickerPresentationTests: XCTestCase {
    private var versions: [MediaVersion] {
        [
            MediaVersion(
                id: "remux",
                fileName: "https://media.example/stream?torrent_name=Movie.Extended.2160p.REMUX.HEVC.TrueHD-GROUP.mkv&id=tt123&media_type=movie",
                edition: "Extended", height: 2160, bitrate: 80_000_000, sizeBytes: 42_000_000_000,
                duration: 7_200, videoCodec: "hevc", videoRange: "SDR", audioCodec: "truehd", audioChannels: 8,
                sourceMetadata: .init(
                    video: .init(codec: "hevc", width: 3840, height: 2160, bitDepth: 10, videoRange: "SDR"),
                    audioLanguages: ["fra", "deu", "spa", "eng", "ita", "por", "jpn", "kor", "zho", "ara", "en"]
                )
            ),
            MediaVersion(id: "current", name: "Current HDR copy", height: 1080, videoRange: "HDR10")
        ]
    }

    func testDetailPopoverKeepsVersionFactsReadableOnPhoneAndPad() async throws {
        for (width, typeSize) in [(320.0, DynamicTypeSize.large), (768.0, .large), (390.0, .accessibility2)] {
            try await assertFacts(
                PlozziOSVersionPickerPopover(versions: versions, selectedVersionID: "remux", onSelectVersion: { _ in }),
                width: width, typeSize: typeSize, name: "version-detail"
            )
        }
    }

    func testPlayerAndSDRSheetsUseTheSameRichVersionFacts() async throws {
        let item = MediaItem(id: "movie", title: "Movie", kind: .movie, versions: versions)
        for onlySDR in [false, true] {
            for width in [320.0, 768.0] {
                try await assertFacts(
                    PlozziOSPlayerVersionSheet(item: item, mediaSourceID: "current", onlySDR: onlySDR, onSelect: { _ in }),
                    width: width, typeSize: .large, name: onlySDR ? "version-player-sdr" : "version-player"
                )
            }
        }
    }

    func testContextMenuPickerUsesTheSameVersionCards() async throws {
        try await assertFacts(
            MediaVersionPicker(versions: versions, selectedVersionID: "remux", onSelect: { _ in }),
            width: 390, typeSize: .large, name: "version-context"
        )
    }

    func testExplicitAudioPreferenceChangesTheCompactLanguageWithoutInventingTracks() async throws {
        try await assertFacts(
            MediaVersionPicker(versions: versions, selectedVersionID: "remux", onSelect: { _ in }),
            width: 390, typeSize: .large, name: "version-french-preference",
            preferredLanguage: "fra", visibleLanguage: "French", hiddenLanguage: "English"
        )
    }

    private func assertFacts<Content: View>(
        _ content: Content, width: CGFloat, typeSize: DynamicTypeSize, name: String,
        preferredLanguage: String = "en", visibleLanguage: String = "English", hiddenLanguage: String = "French"
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: width >= 768 ? 1024 : 844)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: content
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.versionPickerAudioLanguage, preferredLanguage)
            .environment(\.themePalette, .dark)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.horizontalSizeClass, width >= 768 ? .regular : .compact)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(window.bounds.width, width, accuracy: 0.5)
        let scroll = try XCTUnwrap(scrollView(in: window))
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        var visible = ""
        var observedBadgeFooter = false
        for (index, offset) in stride(from: top, through: bottom + scroll.bounds.height / 2, by: scroll.bounds.height / 2).enumerated() {
            scroll.setContentOffset(CGPoint(x: 0, y: min(offset, bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(Int(width))-\(typeSize)-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.001
            request.customWords = ["4K", "HEVC", "Mbps", "TrueHD"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let results = request.results ?? []
            visible += " " + results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            if let filename = results.first(where: {
                $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains("GROUP.mkv") == true
            }), let language = results.first(where: {
                $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(visibleLanguage) == true
            }) {
                XCTAssertLessThan(language.boundingBox.midY, filename.boundingBox.midY,
                                  "Language badges must sit below the release filename.")
                observedBadgeFooter = true
            }
            let inverted = CIImage(cgImage: try XCTUnwrap(image.cgImage)).applyingFilter("CIColorInvert")
            let invertedImage = try XCTUnwrap(CIContext().createCGImage(inverted, from: inverted.extent))
            try VNImageRequestHandler(cgImage: invertedImage).perform([request])
            visible += " " + (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            if offset >= bottom { break }
        }
        for fact in ["Extended", "4K", "42 GB", visibleLanguage, "+9", "HEVC", "TrueHD", "80 Mbps", "2h", "GROUP.mkv"] {
            XCTAssertTrue(visible.localizedCaseInsensitiveContains(fact), "Missing \(fact) in \(name) at \(width): \(visible)")
        }
        XCTAssertTrue(observedBadgeFooter, "The version card's filename and badge footer must remain visible together.")
        XCTAssertFalse(visible.contains("torrent_name"))
        XCTAssertFalse(visible.contains("media_type"))
        XCTAssertFalse(visible.contains(hiddenLanguage), "Additional languages belong behind the compact count, not ten chips.")
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}
#endif
