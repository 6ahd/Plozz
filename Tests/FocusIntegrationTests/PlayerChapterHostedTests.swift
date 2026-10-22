import CoreModels
import CoreUI
@testable import FeaturePlayback
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class PlayerChapterHostedTests: XCTestCase {
    func testChapterCardsRenderAndNativeFocusSurvivesPlayheadUpdates() async throws {
        try await waitUntil {
            UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        for reducedGlass in [false, true] {
            let model = PlayerControlsModel()
            model.duration = 600
            model.currentSeconds = 100
            model.infoCard.chapters = [
                .init(start: 0, title: "Opening"),
                .init(start: 180, title: "The journey"),
                .init(start: 360)
            ]
            let driver = ChapterFocusDriver()
            window.rootViewController = UIHostingController(rootView:
                ChapterFocusFixture(model: model, driver: driver)
                    .frame(width: 1600)
                    .environment(\.plozzReducePanelGlass, reducedGlass)
                    .environment(\.colorScheme, .dark)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black)
            )
            window.makeKeyAndVisible()
            try await waitUntil { driver.requestFocus != nil }
            for target in [PlayerControls.FocusSlot.chapter(0), .chapter(180), .button(.chapters)] {
                let before = UIFocusSystem.focusSystem(for: window)?.focusedItem
                driver.requestFocus?(target)
                try await waitUntil {
                    guard let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem else { return false }
                    return focused !== before && driver.observedFocus == target
                }
            }
            driver.requestFocus?(.chapter(180))
            try await waitUntil { driver.observedFocus == .chapter(180) }
            let focused = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
            for time in [179.9, 180, 359.9, 360] {
                model.currentSeconds = time
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertTrue(UIFocusSystem.focusSystem(for: window)?.focusedItem === focused)
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([recognition])
            let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            for expected in ["Opening", "The journey", "Chapter 3", "3:00", "6:00"] {
                XCTAssertTrue(text.localizedCaseInsensitiveContains(expected), "Missing chapter content: \(text)")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Chapter cards - \(reducedGlass ? "reduced" : "native glass")"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class ChapterFocusDriver {
    var requestFocus: ((PlayerControls.FocusSlot) -> Void)?
    var observedFocus: PlayerControls.FocusSlot?
}

private struct ChapterFocusFixture: View {
    let model: PlayerControlsModel
    let driver: ChapterFocusDriver
    @FocusState private var focus: PlayerControls.FocusSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Button("Chapters") {}
                .focused($focus, equals: .button(.chapters))
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            PlayerChapterPanel(model: model, spoilerSettings: .default, focus: $focus) { _ in }
        }
        .onAppear {
            driver.requestFocus = { focus = $0 }
            focus = .button(.chapters)
        }
        .onChange(of: focus) { _, value in driver.observedFocus = value }
        .onDisappear { driver.requestFocus = nil }
    }
}
