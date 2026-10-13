#if os(iOS)
import CoreUI
import FeatureHomeCore
import SwiftUI
import UIKit
import XCTest
@testable import AppShelliOS

@MainActor
final class HomeModelLifetimeTests: XCTestCase {
    func testTabShellProvidesProfilesToHomeLiveTVScopeOnPhoneAndTablet() async throws {
        let app = PlozziOSAppModel()
        let original = app.profiles.activeProfileID
        let profile = app.profiles.add(name: "Home environment fixture")
        defer {
            app.profiles.select(original)
            app.profiles.remove(profile.id)
        }
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        for (width, sizeClass) in [
            (CGFloat(390), UserInterfaceSizeClass.compact), (834, .regular)
        ] {
            app.profiles.select(original)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1024)
            let host = UIHostingController(rootView:
                PlozziOSTabShell(
                    appModel: app, homeViewModelBox: LazyViewState<HomeViewModel>(), onAddServer: {},
                    showingSettings: .constant(false), showingProfileSwitcher: .constant(false),
                    deferredPairingURL: .constant(nil), systemColorScheme: .dark
                )
                .environment(app)
                .environment(HeroTrailerController())
                .environment(PlozziOSSidebarGeometryModel())
                .environment(\.themePalette, .dark)
                .environment(\.horizontalSizeClass, sizeClass)
            )
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await waitForTabs(in: host, window: window)

            app.profiles.select(profile.id)
            try await waitForTabs(in: host, window: window)
        }
    }

    private func waitForTabs(in host: UIViewController, window: UIWindow) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        repeat {
            try await Task.sleep(for: .milliseconds(16))
            window.layoutIfNeeded()
            if let tabs = tabController(in: host), tabs.view.window === window { return }
        } while ContinuousClock.now < deadline
        XCTFail("The tab shell must render its profile-dependent Live TV scope.")
    }

    private func tabController(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        return controller.children.lazy.compactMap { self.tabController(in: $0) }.first
    }

    func testRootUpdatesReuseTheSameHomeModel() {
        let app = PlozziOSAppModel()
        let box = LazyViewState<HomeViewModel>()
        var models: [HomeViewModel] = []
        let start = ContinuousClock.now
        for index in 0..<24 {
            let shell = PlozziOSTabShell(
                appModel: app, homeViewModelBox: box, onAddServer: {},
                showingSettings: .constant(index.isMultiple(of: 2)),
                showingProfileSwitcher: .constant(false),
                deferredPairingURL: .constant(nil),
                systemColorScheme: index.isMultiple(of: 2) ? .dark : .light
            )
            models.append(shell.sharedHomeViewModel)
        }
        let constructions = Set(models.map(ObjectIdentifier.init)).count
        print("Home root updates: 24; models: \(constructions); elapsed: \(start.duration(to: .now))")
        XCTAssertEqual(constructions, 1, "Root presentation updates must not rehydrate disposable Home models.")
    }

    func testProfileSwitchReplacesTheModelBeforeRenderingTheNewScope() {
        let app = PlozziOSAppModel()
        let original = app.profiles.activeProfileID
        let profile = app.profiles.add(name: "Home lifetime fixture")
        defer {
            app.profiles.select(original)
            app.profiles.remove(profile.id)
        }
        let box = LazyViewState<HomeViewModel>()
        func model() -> HomeViewModel {
            PlozziOSTabShell(
                appModel: app, homeViewModelBox: box, onAddServer: {},
                showingSettings: .constant(false), showingProfileSwitcher: .constant(false),
                deferredPairingURL: .constant(nil), systemColorScheme: .dark
            ).sharedHomeViewModel
        }
        let first = model()
        XCTAssertTrue(first === model())
        app.profiles.select(profile.id)
        let second = model()
        XCTAssertFalse(first === second)
        XCTAssertTrue(second === model())
        app.profiles.select(original)
        let restored = model()
        XCTAssertFalse(second === restored)
        XCTAssertFalse(first === restored, "Do not revive an obsolete credential/cache snapshot.")
    }
}
#endif
