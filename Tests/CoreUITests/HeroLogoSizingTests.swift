import CoreModels
import XCTest
@testable import CoreUI

final class HeroLogoSizingTests: XCTestCase {
    func testDefaultPreservesExistingBoxesExactly() {
        for layout in [HeroLogoSizing.Layout.television, .compact, .regular] {
            let budget = layout.budget
            XCTAssertEqual(
                HeroLogoSizing.box(for: layout),
                HeroLogoFit.pinnedBox(budget: budget, drawnWidth: budget.width)
            )
        }
        XCTAssertEqual(HeroLogoSizing.box(for: .showcase), CGSize(width: 440, height: 124))
    }

    func testEveryShapeGrowsMonotonicallyWithoutDistortionOrEscapingItsSurface() {
        for layout in [HeroLogoSizing.Layout.television, .showcase, .compact, .regular] {
            for aspect: CGFloat in [0.08, 0.22, 0.75, 1.4, 3] {
                var previous = CGSize.zero
                let availableWidth: CGFloat = layout == .compact ? 346 : 900
                for size in HeroLogoSize.allSizes {
                    let box = HeroLogoSizing.box(for: layout, size: size, availableWidth: availableWidth)
                    let fitted = HeroLogoFit.fittedSize(
                        for: CGSize(width: 1000, height: 1000 * aspect),
                        maxWidth: box.width, maxHeight: box.height,
                        coverage: 0.32, constrainsToBounds: layout.constrainsToBounds
                    )
                    XCTAssertEqual(fitted.height / fitted.width, aspect, accuracy: 0.0001)
                    XCTAssertGreaterThanOrEqual(fitted.width + 0.001, previous.width)
                    XCTAssertGreaterThanOrEqual(fitted.height + 0.001, previous.height)
                    XCTAssertLessThanOrEqual(fitted.width, availableWidth + 0.001)
                    XCTAssertLessThanOrEqual(fitted.height, layout == .showcase ? 186 : 360)
                    previous = fitted
                }
            }
        }
    }

    func testTVWordmarksUseTheSameDimensionalScaleAtEveryStop() {
        for layout in [HeroLogoSizing.Layout.television, .showcase] {
            func fitted(_ size: HeroLogoSize) -> CGSize {
                let box = HeroLogoSizing.box(for: layout, size: size)
                return HeroLogoFit.fittedSize(
                    for: CGSize(width: 600, height: 100), maxWidth: box.width,
                    maxHeight: box.height, constrainsToBounds: layout.constrainsToBounds
                )
            }
            let baseline = fitted(.default)
            for size in HeroLogoSize.allSizes {
                XCTAssertEqual(fitted(size).width / baseline.width, size.scale, accuracy: 0.001)
                XCTAssertEqual(fitted(size).height / baseline.height, size.scale, accuracy: 0.001)
            }
        }
    }
}
