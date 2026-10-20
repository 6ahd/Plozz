#if os(iOS)
import CoreUI
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HeroGlassButtonPresentationTests: XCTestCase {
    func testCircularGlassRetainsItsTouchTargetAtEveryTextSize() {
        for size in [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5] {
            let button = Button {} label: { Image(systemName: "bookmark") }
                .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .secondary, circular: true))
                .environment(\.dynamicTypeSize, size)
            XCTAssertEqual(measure(button, width: 48), CGSize(width: 48, height: 48))
        }
    }

    func testProminentGlassRetainsMinimumWidthAndAccessibleWrapping() {
        let regular = measure(play(wraps: false, minimumWidth: 180), width: 2_000)
        XCTAssertGreaterThanOrEqual(regular.width, 180)
        XCTAssertGreaterThanOrEqual(regular.height, 48)
        let wrapped = measure(play(wraps: true), width: 145)
        XCTAssertLessThanOrEqual(wrapped.width, 145)
        XCTAssertGreaterThan(wrapped.height, regular.height)
    }

    func testGlassRowKeepsOverflowWithinPhoneAndTabletWidths() {
        for width in [CGFloat(276), 331, 386, 720] {
            for typeSize in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                let row = ViewThatFits(in: .horizontal) {
                    ForEach((0...4).reversed(), id: \.self) { extras in
                        HeroActionRow {
                            self.play(wraps: false, minimumWidth: 180)
                            ForEach(0..<extras, id: \.self) { _ in
                                Button {} label: { Image(systemName: "bookmark") }
                                    .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .secondary, circular: true))
                            }
                        }
                    }
                    HeroActionRow(stacksVertically: true) { self.play(wraps: true) }
                }
                .environment(\.dynamicTypeSize, typeSize)
                XCTAssertLessThanOrEqual(measure(row, width: width).width, width + 0.5)
            }
        }
    }

    func testReducedGlassAndTransparencyKeepTheExistingFallback() {
        for reduceGlass in [false, true] {
            for kind in [TouchHeroActionButtonStyle.Kind.primary, .secondary] {
                let label = Button("Play", action: {})
                let existing = measure(label.buttonStyle(TouchHeroActionButtonStyle(kind: kind)), width: 300)
                let actual = measure(label
                    .buttonStyle(PlozziOSHeroActionButtonStyle(kind: kind))
                    .environment(\.plozzReducePanelGlass, reduceGlass)
                    .environment(\.plozzReduceTransparency, !reduceGlass), width: 300)
                XCTAssertEqual(actual, existing)
            }
        }
    }

    private func play(wraps: Bool, minimumWidth: CGFloat? = nil) -> some View {
        Button {} label: {
            PlayResumeButtonLabel(
                title: "Resume", progress: 0.4, remainingText: "43m",
                seasonEpisodeText: "S20, E100", onLight: true,
                spacing: 10, capsuleWidth: 60, wrapsText: wraps
            )
        }
        .buttonStyle(PlozziOSHeroActionButtonStyle(kind: .primary, minimumWidth: minimumWidth))
    }

    private func measure(_ view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2_000))
    }
}
#endif
