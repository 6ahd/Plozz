#if os(iOS)
import CoreModels
import CoreUI
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class SeasonRequestLayoutTests: XCTestCase {
    func testFullRequestConfirmationAndReleaseWaitFitPhoneAndTabletLayouts() throws {
        let presentation = SeasonRequestPresentation(availability: .init(status: .processing, seasons: [
            .init(number: 1, title: "Season 1", status: .processing,
                  premiereDate: MediaItem.calendarDayReleaseDate(from: "2099-10-20"))
        ]))
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let label = PlozziOSSeasonRequestSummaryLabel(presentation: presentation)
                    .environment(\.dynamicTypeSize, typeSize)
                let host = UIHostingController(rootView: label)
                let ideal = host.sizeThatFits(in: CGSize(width: 2_000, height: 3_000))
                let narrow = host.sizeThatFits(in: CGSize(width: width - 40, height: 3_000))
                XCTAssertLessThanOrEqual(narrow.width, width - 40 + 0.5)
                if ideal.width > width - 40 {
                    XCTAssertGreaterThan(narrow.height, ideal.height, "Both facts must wrap, not truncate.")
                }
                let compact = actionRow(presentation, vertical: false, trailerTitle: false)
                    .environment(\.dynamicTypeSize, typeSize)
                let compactSize = UIHostingController(rootView: compact)
                    .sizeThatFits(in: CGSize(width: 2_000, height: 3_000))
                let row = ViewThatFits(in: .horizontal) {
                    actionRow(presentation, vertical: false, trailerTitle: true)
                    actionRow(presentation, vertical: false, trailerTitle: false)
                    actionRow(presentation, vertical: true, trailerTitle: false)
                }
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.locale, Locale(identifier: "en"))
                let fitted = UIHostingController(rootView: row)
                    .sizeThatFits(in: CGSize(width: width, height: 3_000))
                XCTAssertLessThanOrEqual(fitted.width, width + 0.5)
                if typeSize == .large, width >= 331 {
                    XCTAssertLessThanOrEqual(compactSize.width, width)
                    XCTAssertEqual(fitted.height, compactSize.height, accuracy: 1,
                                   "A regular phone must keep the status beside the secondary actions.")
                }
                let renderer = ImageRenderer(content: row.frame(width: width).padding(16).background(.black))
                renderer.scale = 2
                let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
                attachment.name = "request-release-\(Int(width))pt-\(typeSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func actionRow(
        _ presentation: SeasonRequestPresentation, vertical: Bool, trailerTitle: Bool
    ) -> some View {
        HeroActionRow(stacksVertically: vertical) {
            Button {} label: { PlozziOSSeasonRequestSummaryLabel(presentation: presentation) }
                .buttonStyle(TouchHeroActionButtonStyle(kind: .secondary))
            Button {} label: {
                if trailerTitle { Label("Trailer", systemImage: "film.fill") }
                else { Image(systemName: "film.fill") }
            }
            .buttonStyle(TouchHeroActionButtonStyle(kind: .secondary, circular: !trailerTitle))
            Button {} label: { Image(systemName: "bookmark") }
                .buttonStyle(TouchHeroActionButtonStyle(kind: .secondary, circular: true))
        }
    }
}
#endif
