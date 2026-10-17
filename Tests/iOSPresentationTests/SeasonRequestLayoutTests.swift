#if os(iOS)
import CoreModels
import CoreUI
import FeatureHomeCore
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import AppShelliOS

@MainActor
final class SeasonRequestLayoutTests: XCTestCase {
    private let item = MediaItem(id: "unreleased-series", title: "Phony", kind: .series)
    private var availability: MediaRequestAvailability {
        .init(status: .processing, seasons: [
            .init(number: 1, title: "Season 1", status: .processing,
                  premiereDate: MediaItem.calendarDayReleaseDate(from: "2099-10-20"))
        ])
    }

    private var request: PlozziOSHeroRequest {
        .init(
            cta: .requested, isRequesting: false, actingName: nil, onRequest: { _ in },
            seasonAvailability: availability, onRequestSeasons: { _ in },
            onOpenSeasonRequests: {}
        )
    }

    func testActualDetailHeroUsesOverflowBeforeStackingAndKeepsButtonsTheSameHeight() throws {
        let app = PlozziOSAppModel()
        let button = PlozziOSHeroRequestButton(item: item, request: request)
            .environment(\.dynamicTypeSize, .large)
        let primary = size(button, width: 2_000)
        XCTAssertEqual(primary.height, 48, accuracy: 0.5,
                       "The complete request status must remain a normal single-line button, not a subtitle card.")
        let overflowSpacingAndWidth: CGFloat = 12 + 48
        for width in [primary.width + overflowSpacingAndWidth - 2,
                      primary.width + overflowSpacingAndWidth + 2, 500, 720] {
            let baseline = foreground(app: app, extras: false)
            let actual = foreground(app: app, extras: true)
            let baselineSize = size(baseline, width: width)
            let actualSize = size(actual, width: width)
            XCTAssertLessThanOrEqual(actualSize.width, width + 0.5)
            if width >= primary.width + overflowSpacingAndWidth {
                XCTAssertEqual(actualSize.height, baselineSize.height, accuracy: 1,
                               "Secondary actions must enter the real overflow menu before the row grows taller.")
            } else {
                XCTAssertEqual(actualSize.height, baselineSize.height + overflowSpacingAndWidth, accuracy: 1,
                               "Only the request and one overflow trigger may stack at the final fallback.")
            }
            let image = try capture(actual, width: width, name: "actual-detail-overflow-\(Int(width))pt")
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
            let lines = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(lines.contains { $0.contains("Requested") && $0.contains("Awaiting Release") },
                          "Both facts must appear together on one line: \(lines)")
            if width < 500 {
                XCTAssertFalse(lines.contains { $0 == "Trailer" },
                               "Trailer must fold rather than forcing a taller request button.")
            }
        }
    }

    func testActualDetailHeroPreservesTheCompleteStatusAtPhoneTabletAndLargeTextSizes() throws {
        let app = PlozziOSAppModel()
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let view = foreground(app: app, extras: true, typeSize: typeSize)
                XCTAssertLessThanOrEqual(size(view, width: width).width, width + 0.5)
                _ = try capture(view, width: width, name: "actual-detail-\(Int(width))pt-\(typeSize)")
            }
        }
    }

    private func foreground(
        app: PlozziOSAppModel, extras: Bool, typeSize: DynamicTypeSize = .large
    ) -> some View {
        let presentation = HeroPresentation(item: item, artworkStyle: .compactPortrait, surface: .detail)
        return PlozziOSDetailHeroForeground(
            item: item, rootItem: item, playableItem: nil,
            sources: [], selectedSourceAccountID: nil,
            versions: [], selectedVersionID: nil,
            onSelectSource: { _ in }, onSelectVersion: { _ in },
            presentation: presentation, fallbackPresentation: presentation,
            style: .compactPortrait,
            actionHandler: RequestLayoutActions(showsWatchlist: extras),
            onPlay: { _, _ in }, trailerItem: extras ? item : nil,
            onPlayTrailer: extras ? { _ in } : nil, heroRequest: request
        )
        .environment(app)
        .environment(\.dynamicTypeSize, typeSize)
        .environment(\.locale, Locale(identifier: "en"))
        .environment(\.themePalette, ThemePalette.dark)
        .environment(\.colorScheme, .dark)
    }

    private func size(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 3_000))
    }

    private func capture(_ view: some View, width: CGFloat, name: String) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: width).padding(16).background(.black))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}

@MainActor
private final class RequestLayoutActions: MediaItemActionHandling {
    let showsWatchlist: Bool
    init(showsWatchlist: Bool) { self.showsWatchlist = showsWatchlist }
    func actions(for item: MediaItem, context: MediaItemActionContext) -> [MediaItemAction] {
        showsWatchlist ? [.addToWatchlist] : []
    }
    func perform(_ action: MediaItemAction, on item: MediaItem, context: MediaItemActionContext) {}
}
#endif
