#if os(iOS)
import CoreModels
import CoreUI
@testable import FeatureSettings
import Observation
import SwiftUI
import UIKit
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
}
#endif
