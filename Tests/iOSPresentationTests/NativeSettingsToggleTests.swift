#if os(iOS)
import CoreModels
import CoreUI
@testable import FeatureSettings
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class NativeSettingsToggleTests: XCTestCase {
    @Observable
    final class Model {
        var isOn = false
        var isDisabled = false
        var writes = 0

        var binding: Binding<Bool> {
            Binding(
                get: { self.isOn },
                set: { self.isOn = $0; self.writes += 1 }
            )
        }
    }

    func testGroupedSettingsUseNativeSwitchesAndPreserveBindings() async throws {
        try await verifyNativeSwitch(grouped: true)
    }

    func testSharedSettingsStyleUsesNativeSwitchesOnMobile() async throws {
        try await verifyNativeSwitch(grouped: false)
    }

    func testHeroRootUsesInlineControlsAndShowsPageStatesAtPhoneAndTabletWidths() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for width: CGFloat in [390, 834] {
            let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
            let background = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())
            hero.settings.autoAdvance = false
            hero.settings.showsRatings = false
            background.settings.homeTrailerEnabled = false
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                SettingsPageList {
                    HeroSettingsControls(libraries: [], accounts: [])
                }
                .navigationTitle("Customize Home")
            }
            .environment(hero)
            .environment(background)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark))
            window.makeKeyAndVisible()
            try await settle(window)
            let root = try captureText(window, name: "hero-root-mobile-\(Int(width))")
            for label in ["Titles shown in hero", "Hide watched titles", "Number of titles",
                          "Change titles automatically", "Ratings", "Off", "Trailers"] {
                XCTAssertTrue(root.contains(label), root)
            }
            for label in ["Appearance", "Rotation", "Content", "Show ratings", "Seconds per title",
                          "Play trailer behind the hero", "Start muted"] {
                XCTAssertFalse(root.contains(label), root)
            }
            let controls = listedSwitches(in: window).sorted {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            }
            XCTAssertEqual(controls.count, 3, "Only enable, watched, and automatic changes are switches on the root.")
            let automatic = try XCTUnwrap(controls.indices.contains(2) ? controls[2] : nil)
            automatic.setOn(true, animated: false)
            automatic.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertTrue(hero.settings.autoAdvance)
            let advanced = try captureText(window, name: "hero-automatic-mobile-\(Int(width))")
            XCTAssertTrue(advanced.contains("Seconds per title"), advanced)

            hero.settings.showsRatings = true
            background.settings.homeTrailerEnabled = true
            try await settle(window)
            let expanded = try captureText(window, name: "hero-expanded-mobile-\(Int(width))")
            XCTAssertFalse(expanded.contains("Start muted"), expanded)
            XCTAssertTrue(expanded.contains("On"), expanded)
            XCTAssertFalse(expanded.contains("Show ratings"), expanded)
            XCTAssertFalse(expanded.contains("Show Common Sense age"), expanded)

            let enable = try XCTUnwrap(listedSwitches(in: window).min {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            })
            enable.setOn(false, animated: false)
            enable.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertFalse(hero.settings.isEnabled)
            XCTAssertEqual(listedSwitches(in: window).count, 1)
            XCTAssertTrue(hero.settings.autoAdvance)
            XCTAssertTrue(hero.settings.showsRatings)
            XCTAssertTrue(background.settings.homeTrailerEnabled)

            window.rootViewController = UIHostingController(rootView: NavigationStack {
                HeroSettingsScreen(page: .ratings, libraries: [], accounts: [])
            }
            .environment(hero)
            .environment(background)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark))
            try await settle(window)
            XCTAssertEqual(listedSwitches(in: window).count, 2)
            let ratings = try captureText(window, name: "hero-ratings-mobile-\(Int(width))")
            XCTAssertTrue(ratings.contains("Show ratings"), ratings)
            XCTAssertTrue(ratings.contains("Show Common Sense age"), ratings)
            XCTAssertTrue(ratings.contains("Maximum ratings shown"), ratings)
            XCTAssertTrue(ratings.contains("Shows fewer when fewer ratings are available"), ratings)
            let showRatings = try XCTUnwrap(listedSwitches(in: window).min {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            })
            showRatings.setOn(false, animated: false)
            showRatings.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertFalse(hero.settings.showsRatings)
            XCTAssertEqual(listedSwitches(in: window).count, 1)

            window.rootViewController = UIHostingController(rootView: NavigationStack {
                HeroSettingsScreen(page: .trailers, libraries: [], accounts: [])
            }
            .environment(hero)
            .environment(background)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark))
            try await settle(window)
            XCTAssertEqual(listedSwitches(in: window).count, 2)
            let trailers = try captureText(window, name: "hero-trailers-mobile-\(Int(width))")
            XCTAssertTrue(trailers.contains("Play trailer behind the hero"), trailers)
            XCTAssertTrue(trailers.contains("Start muted"), trailers)
            let playTrailer = try XCTUnwrap(listedSwitches(in: window).min {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            })
            playTrailer.setOn(false, animated: false)
            playTrailer.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertFalse(background.settings.homeTrailerEnabled)
            XCTAssertEqual(listedSwitches(in: window).count, 1)
        }
    }

    func testHeroSourceGroupsKeepNativeSwitchesSeparateFromNavigationRows() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for width: CGFloat in [390, 834] {
            let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
            let background = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())
            hero.settings.sources = [.randomFromLibrary, .collection, .featured]
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                HeroSettingsScreen(page: .titles, libraries: [], accounts: [])
            }
            .environment(hero)
            .environment(background)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .dark))
            window.makeKeyAndVisible()
            try await settle(window)
            let sourceText = try captureText(window, name: "hero-sources-mobile-\(Int(width))")
            for title in ["Random from Library", "Choose libraries", "Choose collections", "Discovery providers"] {
                XCTAssertTrue(sourceText.contains(title), sourceText)
            }
            let switches = listedSwitches(in: window).sorted {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            }
            XCTAssertEqual(switches.count, 6)
            let random = try XCTUnwrap(switches.indices.contains(2) ? switches[2] : nil)
            var ancestor = random.superview
            while ancestor != nil && !(ancestor is UICollectionViewCell) { ancestor = ancestor?.superview }
            let cell = try XCTUnwrap(ancestor as? UICollectionViewCell)
            XCTAssertLessThan(cell.bounds.height, 90, "The source and its navigation link must be separate native rows.")
            random.setOn(false, animated: false)
            random.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertFalse(hero.settings.sources.contains(.randomFromLibrary))
            XCTAssertTrue(hero.settings.sources.contains(.collection))
            XCTAssertTrue(hero.settings.sources.contains(.featured))
            let collapsed = try captureText(window, name: "hero-sources-collapsed-mobile-\(Int(width))")
            XCTAssertFalse(collapsed.contains("Choose libraries"), collapsed)
            XCTAssertTrue(collapsed.contains("Choose collections"), collapsed)
            XCTAssertTrue(collapsed.contains("Discovery providers"), collapsed)
        }
    }

    func testHeroSubpagesUseNativeSwitchesAndLiveKidsPolicyAtPhoneAndTabletWidths() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for width: CGFloat in [390, 834] {
            let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
            let background = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1200)
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                HeroSettingsScreen(page: .discovery, libraries: [], accounts: [])
            }
            .environment(hero)
            .environment(background)
            .environment(\.colorScheme, .dark))
            window.makeKeyAndVisible()
            try await settle(window)
            XCTAssertEqual(listedSwitches(in: window).count, 5, "Attribution plus four providers use native switches.")
            let labels = try XCTUnwrap(listedSwitches(in: window).min {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            })
            labels.setOn(true, animated: false)
            labels.sendActions(for: .valueChanged)
            try await settle(window)
            XCTAssertTrue(hero.settings.showsDiscoverySources)
            XCTAssertEqual(hero.settings.discoverySources, HeroDiscoverySource.defaultSelection)
            hero.setDiscoveryPolicy { false }
            let deadline = ContinuousClock.now + .seconds(2)
            repeat {
                try await settle(window)
            } while !listedSwitches(in: window).isEmpty && ContinuousClock.now < deadline
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = "kids-discovery-mobile-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(listedSwitches(in: window).isEmpty, "An open Discovery page must lose its controls in Kids mode.")
            XCTAssertTrue(hero.settings.showsDiscoverySources, "Restricting Discovery must not erase saved preferences.")
            XCTAssertFalse(hero.effectiveSettings.showsDiscoverySources)
        }
    }

    private func verifyNativeSwitch(grouped: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for width: CGFloat in [390, 834] {
            for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
                for scheme: ColorScheme in [.light, .dark] {
                    let model = Model()
                    window.frame = CGRect(x: 0, y: 0, width: width, height: 1100)
                    window.rootViewController = UIHostingController(rootView:
                        Fixture(model: model, grouped: grouped)
                            .environment(\.layoutDirection, direction)
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, .accessibility1)
                            .tint(scheme == .dark ? .white : .black)
                    )
                    window.makeKeyAndVisible()
                    try await settle(window)
                    let controls = switches(in: window)
                    XCTAssertEqual(controls.count, 1, "Use one UISwitch, not a drawn button or nested toggles.")
                    let control = try XCTUnwrap(controls.first)
                    XCTAssertFalse(control.isOn)
                    XCTAssertTrue(control.isEnabled)
                    XCTAssertNil(control.thumbTintColor, "The system must own the knob's appearance.")
                    if let tint = control.onTintColor?.resolvedColor(with: control.traitCollection) {
                        var red: CGFloat = 0
                        var green: CGFloat = 0
                        var blue: CGFloat = 0
                        var alpha: CGFloat = 0
                        XCTAssertTrue(tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                        XCTAssertGreaterThan(green, red, "Use the system switch tint, not the page's monochrome accent.")
                    }
                    XCTAssertGreaterThan(control.bounds.width, 0)

                    control.setOn(true, animated: false)
                    control.sendActions(for: .valueChanged)
                    try await settle(window)
                    XCTAssertTrue(model.isOn)
                    XCTAssertEqual(model.writes, 1, "A switch activation must write its binding exactly once.")

                    model.isOn = false
                    model.isDisabled = true
                    try await settle(window)
                    let updated = try XCTUnwrap(switches(in: window).first)
                    XCTAssertFalse(updated.isOn, "External setting changes must reach the native control.")
                    XCTAssertFalse(updated.isEnabled)
                    XCTAssertEqual(model.writes, 1, "Rendering or disabling must not mutate the setting.")
                }
            }
        }
    }

    private struct Fixture: View {
        let model: Model
        let grouped: Bool

        var body: some View {
            SettingsPageList {
                if grouped {
                    SettingsSectionGroup {
                        Toggle("Native preference", isOn: model.binding)
                            .disabled(model.isDisabled)
                        if model.isOn {
                            Text("Additional settings")
                        }
                        Button("Separate action") {}
                    }
                } else {
                    Toggle("Native preference", isOn: model.binding)
                        .toggleStyle(SettingsSwitchToggleStyle())
                        .disabled(model.isDisabled)
                }
            }
        }
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
    }

    private func switches(in view: UIView) -> [UISwitch] {
        (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap { switches(in: $0) }
    }

    private func listedSwitches(in view: UIView) -> [UISwitch] {
        if let list = view as? UICollectionView {
            // List retains deleted rows in its reuse pool, outside the presented cells.
            return list.visibleCells.flatMap { switches(in: $0) }
        }
        return view.subviews.flatMap { listedSwitches(in: $0) }
    }

    private func captureText(_ window: UIWindow, name: String) throws -> String {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
#endif
