import CoreModels
import CoreUI
@testable import AppShell
@testable import FeatureSettings
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class ArtworkSettingsHostedTests: XCTestCase {
    func testHeroKeepsEverydayControlsInlineAndReturnsNativeFocusToNamedPages() async throws {
        let namespace = "HeroHierarchyHosted.\(UUID())"
        let models = ProfileSettingsModel(namespace: namespace)
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(namespace) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        models.heroSettingsModel.settings.autoAdvance = false
        models.heroSettingsModel.settings.showsRatings = false
        models.heroBackgroundModel.settings.homeTrailerEnabled = false
        let navigation = SettingsDetailNavigation()
        try await withScreen(content: SettingsDetailPages(navigation: navigation) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsRowMetrics.formSectionSpacing) {
                    HeroSettingsControls(libraries: [], accounts: [])
                }
                .padding(48)
            }
            .buttonStyle(SettingsFocusButtonStyle())
            .toggleStyle(SettingsSwitchToggleStyle())
        } detail: {
            HeroSettingsDestination(libraries: [], accounts: [])
        }
        .frame(width: 1100)
        .environment(models.heroSettingsModel)
        .environment(models.heroBackgroundModel)) { window in
            let root = try await self.capture(window, name: "hero-inline-titles", includeMaster: true)
            for title in ["Hero content sources", "Hide watched content", "Items to show", "Advance automatically"] {
                XCTAssertTrue(root.contains(title), root)
            }
            for title in ["Titles shown in hero", "Automatic changes", "Appearance", "Rotation", "Rotate automatically"] {
                XCTAssertFalse(root.contains(title), root)
            }
            XCTAssertFalse(root.contains("TMDB"), root)
            XCTAssertFalse(root.contains("Show provider labels"), root)
            XCTAssertFalse(root.contains("Seconds per item"), root)
            let scroll = try self.verticalScroll(in: window)
            scroll.setContentOffset(CGPoint(
                x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            ), animated: false)
            let bottom = try await self.capture(window, name: "hero-inline-ratings-trailers", includeMaster: true)
            XCTAssertTrue(bottom.contains("Ratings"), bottom)
            XCTAssertTrue(bottom.contains("Trailers"), bottom)
            XCTAssertTrue(bottom.contains("Off"), bottom)
            XCTAssertFalse(bottom.contains("Show ratings"), bottom)
            XCTAssertFalse(bottom.contains("Play trailer behind the hero"), bottom)
            XCTAssertFalse(bottom.contains("Show Common Sense age"), bottom)
            XCTAssertFalse(bottom.contains("Start muted"), bottom)

            scroll.setContentOffset(.zero, animated: false)
            models.heroSettingsModel.settings.autoAdvance = true
            let automatic = try await self.capture(window, name: "hero-inline-automatic", includeMaster: true)
            XCTAssertTrue(automatic.contains("Seconds per item"), automatic)
            XCTAssertFalse(automatic.localizedCaseInsensitiveContains("Automatic changes"), automatic)
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            for page in [HeroSettingsPage.titles, .ratings, .trailers] {
                if page != .titles {
                    scroll.setContentOffset(CGPoint(
                        x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    ), animated: false)
                    _ = try await self.capture(window, name: "hero-\(page.rawValue)-link", includeMaster: true)
                }
                let openingLabel = try XCTUnwrap(self.collectionLabelFrames(in: window).first {
                    $0.text == String(localized: page.title)
                })
                let center = CGPoint(x: openingLabel.frame.midX, y: openingLabel.frame.midY)
                let originatingLink = try XCTUnwrap(self.focusItems(in: window).first {
                    (try? self.nativeFrame($0, in: window).contains(center)) == true
                })
                let host = try XCTUnwrap(window.rootViewController as? ArtworkFocusRequesting)
                host.artworkFocusTarget = originatingLink
                system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
                system.updateFocusIfNeeded()
                host.artworkFocusTarget = nil
                XCTAssertTrue(system.focusedItem === originatingLink)
                navigation.push(pageID: page.rawValue, animated: false)
                let shown = try await self.capture(window, name: "hero-\(page.rawValue)", includeMaster: true)
                let expected = page == .titles ? "Continue Watching"
                    : page == .ratings ? "Show ratings" : "Play trailer behind the hero"
                XCTAssertTrue(shown.contains(expected), shown)
                if page == .titles {
                    XCTAssertTrue(shown.contains("Hero content sources"), shown)
                }
                XCTAssertFalse(shown.contains("Hide watched content"), shown)
                XCTAssertFalse(navigation.awaitingFocus, "The page must receive native focus, not trap the master pane.")
                if page == .ratings {
                    XCTAssertFalse(shown.contains("Show Common Sense age"), shown)
                    models.heroSettingsModel.settings.showsRatings = true
                    let ratings = try await self.capture(window, name: "hero-ratings-enabled", includeMaster: true)
                    XCTAssertTrue(ratings.contains("Show Common Sense age"), ratings)
                    XCTAssertTrue(ratings.localizedCaseInsensitiveContains("Maximum ratings shown"), ratings)
                    XCTAssertTrue(ratings.contains("Shows fewer when fewer ratings are available"), ratings)
                } else if page == .trailers {
                    XCTAssertFalse(shown.contains("Start muted"), shown)
                    models.heroBackgroundModel.settings.homeTrailerEnabled = true
                    let trailers = try await self.capture(window, name: "hero-trailers-enabled", includeMaster: true)
                    XCTAssertTrue(trailers.contains("Start muted"), trailers)
                }
                navigation.pop(animated: false)
                let returned = try await self.capture(window, name: "hero-return-\(page.rawValue)", includeMaster: true)
                if page != .titles {
                    XCTAssertTrue(returned.contains("On"), returned)
                    XCTAssertFalse(returned.contains("Show Common Sense age"), returned)
                    XCTAssertFalse(returned.contains("Start muted"), returned)
                }
                let label = try XCTUnwrap(self.collectionLabelFrames(in: window).first {
                    $0.text == String(localized: page.title)
                })
                let frame = try self.nativeFrame(try XCTUnwrap(system.focusedItem), in: window)
                XCTAssertTrue(frame.contains(CGPoint(x: label.frame.midX, y: label.frame.midY)),
                              "Return must focus \(page.rawValue), not a competing link. Focus: \(frame), label: \(label.frame)")
            }
            scroll.setContentOffset(.zero, animated: false)
            models.heroSettingsModel.settings.sources = [.featured, .watchlist]
            let selected = try await self.capture(window, name: "hero-selected-source-summary", includeMaster: true)
            XCTAssertTrue(selected.contains("Discovery"), selected)
            XCTAssertTrue(selected.contains("Watchlist"), selected)
            models.heroSettingsModel.setDiscoveryPolicy { false }
            let kids = try await self.capture(window, name: "hero-kids-source-summary", includeMaster: true)
            XCTAssertFalse(kids.contains("Discovery"), kids)
            XCTAssertTrue(kids.contains("Watchlist"), kids)
            models.heroSettingsModel.settings.sources = []
            let empty = try await self.capture(window, name: "hero-empty-source-summary", includeMaster: true)
            XCTAssertTrue(empty.contains("No content sources selected"), empty)
        }
    }

    func testNestedDiscoveryReturnsToTitleSourcesWithoutPoppingTheHeroPage() async throws {
        let namespace = "HeroNestedHosted.\(UUID())"
        let models = ProfileSettingsModel(namespace: namespace)
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(namespace) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let parent = SettingsDetailNavigation()
        let child = SettingsDetailNavigation()
        parent.push(pageID: HeroSettingsPage.titles.rawValue, animated: false)
        try await withScreen(content: HeroSettingsScreen(
            page: .titles, libraries: [], accounts: [], childNavigation: child
        )
        .frame(width: 1100)
        .environment(parent)
        .environment(models.heroSettingsModel)
        .environment(models.heroBackgroundModel)) { window in
            _ = try await self.capture(window, name: "hero-grouped-title-sources", includeMaster: true)
            let sourceLabels = try self.collectionLabelFrames(in: window, attachmentName: "hero-source-label-metrics")
            let random = try XCTUnwrap(sourceLabels.first { $0.text == "Random from Library" })
            let choose = try XCTUnwrap(sourceLabels.first { $0.text == "Choose libraries" })
            XCTAssertEqual(random.frame.height, choose.frame.height, accuracy: 4,
                           "Source switches and their links must use the same text size.")
            XCTAssertEqual(random.frame.minX, choose.frame.minX, accuracy: 2,
                           "Grouped source controls must share a leading text edge.")
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController as? ArtworkFocusRequesting)
            let initialFrame = try self.nativeFrame(try XCTUnwrap(system.focusedItem), in: window)
            XCTAssertEqual(initialFrame.minX, (window.bounds.width - 1100) / 2 + 48
                           + SettingsRowMetrics.formGroupInset, accuracy: 1)
            XCTAssertEqual(initialFrame.width, 1100 - 96 - 2 * SettingsRowMetrics.formGroupInset, accuracy: 1)
            try self.assertConcentricGroup(in: window, focusFrame: initialFrame)
            var sourceFrames: [CGRect] = []
            for label in [random, choose] {
                let center = CGPoint(x: label.frame.midX, y: label.frame.midY)
                let target = try XCTUnwrap(self.focusItems(in: window).first {
                    (try? self.nativeFrame($0, in: window).contains(center)) == true
                })
                sourceFrames.append(try self.nativeFrame(target, in: window))
                host.artworkFocusTarget = target
                system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
                system.updateFocusIfNeeded()
                host.artworkFocusTarget = nil
                XCTAssertTrue(system.focusedItem === target)
                _ = try await self.capture(window, name: "hero-group-focus-\(sourceFrames.count)", includeMaster: true)
            }
            XCTAssertEqual(sourceFrames[0].height, sourceFrames[1].height, accuracy: 1)
            XCTAssertEqual(sourceFrames[1].minY - sourceFrames[0].maxY,
                           SettingsRowMetrics.formRowSpacing, accuracy: 1)
            let scroll = try self.verticalScroll(in: window)
            scroll.setContentOffset(CGPoint(
                x: scroll.contentOffset.x,
                y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            ), animated: false)
            _ = try await self.capture(window, name: "hero-title-source-options", includeMaster: true)
            let label = try XCTUnwrap(self.collectionLabelFrames(in: window)
                .first { $0.text == "Discovery providers" })
            let center = CGPoint(x: label.frame.midX, y: label.frame.midY)
            let target = try XCTUnwrap(self.focusItems(in: window).first {
                (try? self.nativeFrame($0, in: window).contains(center)) == true
            })
            host.artworkFocusTarget = target
            system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
            system.updateFocusIfNeeded()
            host.artworkFocusTarget = nil
            XCTAssertTrue(system.focusedItem === target)
            child.push(pageID: HeroSettingsPage.discovery.rawValue, animated: false)
            let opened = try await self.capture(window, name: "hero-nested-discovery", includeMaster: true)
            XCTAssertTrue(opened.contains("Show provider labels"), opened)
            XCTAssertFalse(child.awaitingFocus)
            child.pop(animated: false)
            _ = try await self.capture(window, name: "hero-nested-titles-return", includeMaster: true)
            XCTAssertTrue(parent.isPresented, "Returning from Discovery must not leave the title-source page.")
            let returnedLabel = try XCTUnwrap(self.collectionLabelFrames(in: window)
                .first { $0.text == "Discovery providers" })
            let frame = try self.nativeFrame(try XCTUnwrap(system.focusedItem), in: window)
            XCTAssertTrue(frame.contains(CGPoint(x: returnedLabel.frame.midX, y: returnedLabel.frame.midY)),
                          "Nested return should retain the source-option link: \(frame), \(returnedLabel.frame)")
        }
    }

    func testOpenDiscoveryPageRemovesProvidersWhenProfileBecomesKids() async throws {
        let namespace = "HeroKidsHosted.\(UUID())"
        let models = ProfileSettingsModel(namespace: namespace)
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(namespace) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        let navigation = SettingsDetailNavigation()
        navigation.push(pageID: HeroSettingsPage.discovery.rawValue, animated: false)
        try await withScreen(content: SettingsDetailPages(navigation: navigation) {
            HeroSettingsControls(libraries: [], accounts: [])
        } detail: {
            HeroSettingsDestination(libraries: [], accounts: [])
        }
        .frame(width: 1100)
        .environment(models.heroSettingsModel)
        .environment(models.heroBackgroundModel)) { window in
            let adult = try await self.capture(window, name: "hero-discovery-providers", includeMaster: true)
            XCTAssertTrue(adult.contains("Show provider labels"), adult)
            XCTAssertTrue(adult.contains("TMDB"), adult)
            models.heroSettingsModel.setDiscoveryPolicy { false }
            let kids = try await self.capture(window, name: "hero-discovery-kids", includeMaster: true)
            XCTAssertTrue(kids.contains("Discovery is unavailable in Kids profiles"), kids)
            XCTAssertFalse(kids.contains("TMDB"), kids)
            XCTAssertFalse(kids.contains("Show provider labels"), kids)
            XCTAssertEqual(try self.collectionLabelFrames(in: window).filter {
                $0.text.trimmingCharacters(in: .letters.inverted) == "Back"
            }.count, 1)
            XCTAssertNotNil(UIFocusSystem.focusSystem(for: window)?.focusedItem)
        }
    }

    func testEmptyHeroPagesEnterTheirSingleBackControl() async throws {
        let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
        hero.setDiscoveryPolicy { false }
        let background = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())
        for page in [HeroSettingsPage.discovery, .libraries] {
            let navigation = SettingsDetailNavigation()
            navigation.push(pageID: page.rawValue, animated: false)
            try await withScreen(content: SettingsDetailPages(navigation: navigation) {
                HeroSettingsControls(libraries: [], accounts: [])
            } detail: {
                HeroSettingsDestination(libraries: [], accounts: [])
            }
                .frame(width: 1100)
                .environment(hero)
                .environment(background)) { window in
                _ = try await self.capture(window, name: "hero-empty-\(page.rawValue)", includeMaster: true)
                let labels = try self.collectionLabelFrames(in: window).filter {
                    $0.text.trimmingCharacters(in: .letters.inverted) == "Back"
                }
                XCTAssertEqual(labels.count, 1)
                let label = try XCTUnwrap(labels.first)
                let focused = try XCTUnwrap(UIFocusSystem.focusSystem(for: window)?.focusedItem)
                XCTAssertTrue(try self.nativeFrame(focused, in: window).contains(
                    CGPoint(x: label.frame.midX, y: label.frame.midY)
                ))
                XCTAssertFalse(navigation.awaitingFocus)
            }
        }
    }

    func testMultipleSelectionsShowTheirLibrariesAndClearingDoesNotSwitchTheBrowsedSource() async throws {
        let provider = HeroPickerHostedProvider(empty: false)
        let account = ResolvedAccount(account: Account(id: "a", from: provider.session), provider: provider)
        let libraries = ["movies", "shows"].map {
            AggregatedLibrary(
                accountID: "a", accountName: "Viewer", serverName: "Server", providerKind: .silo,
                library: MediaLibrary(id: $0, title: $0 == "movies" ? "Movies" : "Shows", kind: $0 == "movies" ? .movie : .series)
            )
        }
        var settings = HeroSettings.default
        settings.collections = libraries.map {
            .init(accountID: "a", libraryID: $0.library.id, collectionID: "\($0.library.id)-collection",
                  title: "\($0.library.id) picks", serverUserID: "viewer")
        }
        let model = HeroSettingsModel(store: InMemoryHeroSettingsStore(settings))
        try await withScreen(content: HeroCollectionPickerView(
            selections: Binding(get: { model.settings.collections }, set: { model.settings.collections = $0 }),
            libraries: libraries, accounts: [account]
        ).frame(width: 1100)) { window in
            let before = try await self.capture(window, name: "hero-multiple-selected-libraries", includeMaster: true)
            XCTAssertTrue(before.contains("Selected collections"), before)
            XCTAssertTrue(before.contains("movies picks"), before)
            XCTAssertTrue(before.contains("shows picks"), before)
            XCTAssertTrue(before.contains("Movies / Server / Viewer"), before)
            XCTAssertTrue(before.contains("Shows / Server / Viewer"), before)
            model.settings.collections = []
            let cleared = try await self.capture(window, name: "hero-cleared-same-library", includeMaster: true)
            XCTAssertFalse(cleared.contains("Selected collections"), cleared)
            XCTAssertTrue(cleared.contains("movies picks"), cleared)
            XCTAssertFalse(cleared.contains("Funny movies"), "Clearing choices must not reset the browsed source: \(cleared)")
        }
    }

    func testCollectionPickerScrollsThroughBottomSafeAreaToScreenEdge() async throws {
        let provider = HeroPickerHostedProvider(empty: false, collectionCount: 20)
        let account = ResolvedAccount(account: Account(id: "a", from: provider.session), provider: provider)
        let navigation = SettingsDetailNavigation()
        navigation.push(animated: false)
        try await withScreen(
            content: SettingsDetailPages(navigation: navigation) {
                Color.clear
            } detail: {
                HeroCollectionPickerView(selections: .constant([]), libraries: [], accounts: [account])
            }.frame(width: 1100),
            bottomSafeArea: 120
        ) { window in
            var pending = [try XCTUnwrap(window.rootViewController?.view)]
            var scrolls: [UIScrollView] = []
            while let view = pending.popLast() {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    scrolls.append(scroll)
                }
                pending.append(contentsOf: view.subviews)
            }
            let scroll = try XCTUnwrap(scrolls.max { $0.bounds.width < $1.bounds.width })
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: 500), animated: false)
            try await Task.sleep(for: .milliseconds(250))
            let innerBottom = window.bounds.maxY - (window.rootViewController?.view.safeAreaInsets.bottom ?? 0)
            let before = try self.collectionLabelFrames(in: window)
            let row = try XCTUnwrap(before.last {
                $0.text.hasPrefix("Collection ") && $0.frame.maxY < innerBottom - 40
            }, "\(before)")
            let baselineOffset = scroll.contentOffset.y
            for targetY in [innerBottom + 30, window.bounds.maxY - 60] {
                let newOffset = baselineOffset + row.frame.minY - targetY
                XCTAssertGreaterThan(newOffset, -scroll.adjustedContentInset.top)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: newOffset), animated: false)
                let text = try await self.capture(window, name: "collections-bottom-\(Int(targetY))", includeMaster: true)
                XCTAssertTrue(text.contains(row.text), "A row below the safe-area edge must remain readable: \(text)")
                let visible = try XCTUnwrap(self.collectionLabelFrames(in: window).first { $0.text == row.text })
                XCTAssertGreaterThan(visible.frame.minY, innerBottom + 15)
                XCTAssertLessThan(visible.frame.maxY, window.bounds.maxY)
                XCTAssertGreaterThan(visible.frame.height, row.frame.height * 0.85)
            }
        }
    }

    func testCustomizationBackAndTitleScrollThroughTheTopSafeAreaWithoutClipping() async throws {
        try await withScreen(
            content: CardCaptionCustomizationContent(settings: .constant(.init(preference: .show)))
                .frame(width: 1100),
            topSafeArea: 60
        ) { window in
            var pending = [try XCTUnwrap(window.rootViewController?.view)]
            var scrolls: [UIScrollView] = []
            while let view = pending.popLast() {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    scrolls.append(scroll)
                }
                pending.append(contentsOf: view.subviews)
            }
            let scroll = try XCTUnwrap(scrolls.max { $0.bounds.width < $1.bounds.width })
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(250))
            _ = try await self.capture(window, name: "labels-before-top-scroll", includeMaster: true)
            let before = try self.collectionLabelFrames(in: window)
            let back = try XCTUnwrap(before.first { $0.text.hasSuffix("Back") }, "\(before)")
            let title = try XCTUnwrap(before.first { $0.text == "Labels by view" })
            let backCenter = CGPoint(x: back.frame.midX, y: back.frame.midY)
            let backItem = try XCTUnwrap(self.focusItems(in: window).first {
                (try? self.nativeFrame($0, in: window).contains(backCenter)) == true
            })
            let backControlFrame = try self.nativeFrame(backItem, in: window)
            let viewport = scroll.convert(scroll.bounds, to: window)
            let innerTop = viewport.minY + scroll.adjustedContentInset.top
            let distance = back.frame.minY - innerTop + 14
            XCTAssertGreaterThan(distance, 20)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: scroll.contentOffset.y + distance), animated: false)
            try await Task.sleep(for: .milliseconds(250))
            _ = try await self.capture(window, name: "labels-crossing-top-inset", includeMaster: true)
            let after = try self.collectionLabelFrames(in: window)
            let scrolledBack = try XCTUnwrap(after.first { $0.text.hasSuffix("Back") },
                                             "Back must remain readable across the top inset: viewport=\(viewport), offset=\(scroll.contentOffset), clips=\(scroll.clipsToBounds), text=\(after)")
            let scrolledTitle = try XCTUnwrap(after.first { $0.text == "Labels by view" })
            XCTAssertLessThan(scrolledBack.frame.minY, innerTop - 8)
            XCTAssertGreaterThan(scrolledBack.frame.height, back.frame.height * 0.85)
            let scrolledControlFrame = try self.nativeFrame(backItem, in: window)
            XCTAssertEqual(backControlFrame.minY - scrolledControlFrame.minY, distance, accuracy: 1)
            XCTAssertEqual(title.frame.minY - scrolledTitle.frame.minY, distance, accuracy: 3,
                           "Neither Back nor the title should be pinned.")
            let text = try await self.capture(window, name: "labels-scrolling-through-top-inset", includeMaster: true)
            XCTAssertTrue(text.contains("Labels are visible in this view"), text)
        }
    }

    func testLabelHelpDescribesTheVisibleAndHiddenSetting() async throws {
        let suite = "LabelVisibilityHelpHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        try await withScreen(content: CardCaptionCustomizationView(cards: cards).frame(width: 1100)) { window in
            for (preference, expected) in [
                (CardCaptionPreference.show, "Labels are visible in this view"),
                (.hide, "Labels are hidden in this view"),
                (.recommended, "Labels are visible except in Showcase and on series artwork")
            ] {
                cards.captions = CardCaptionSettings(preference: preference)
                let text = try await self.capture(window, name: "label-help-\(preference.rawValue)", includeMaster: true)
                XCTAssertTrue(text.contains(expected), text)
                XCTAssertFalse(text.contains("separate from"), text)
            }
        }
    }

    func testCollectionPickerUsesPaneHeaderAndReturnsRealFocus() async throws {
        let provider = HeroPickerHostedProvider(empty: false)
        let account = ResolvedAccount(account: Account(id: "a", from: provider.session), provider: provider)
        let navigation = SettingsDetailNavigation()
        let picker = HeroCollectionPickerView(selections: .constant([]), libraries: [], accounts: [account])
        try await withScreen(content: NavigationStack {
            HStack(spacing: 0) {
                Text("Customize Home").frame(width: 768)
                SettingsDetailPages(navigation: navigation) {
                    SettingsDetailLink {
                        picker
                    } label: {
                        Text("Choose collection")
                    }
                } detail: {
                    picker
                }
            }
            .ignoresSafeArea()
        }) { window in
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            navigation.push(animated: false)
            let deadline = ContinuousClock.now + .seconds(3)
            while navigation.awaitingFocus, ContinuousClock.now < deadline {
                system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
                system.updateFocusIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(navigation.awaitingFocus)
            let focused = try self.nativeFocusedFrame(system, in: window)
            let labels = try self.collectionLabelFrames(in: window)
            let sourceLabel = try XCTUnwrap(labels.first { $0.text == "Personal collections" })
            XCTAssertTrue(focused.contains(CGPoint(x: sourceLabel.frame.midX, y: sourceLabel.frame.midY)),
                          "Entry must reach the real source row, not Back: \(focused), label: \(sourceLabel.frame)")
            let heading = try XCTUnwrap(labels.first { $0.text == "Choose collections" })
            XCTAssertGreaterThan(heading.frame.minX, 800)
            XCTAssertLessThan(heading.frame.height, 60, "Use the pane heading, not full-page navigation chrome.")
            let text = try await self.capture(window, name: "hero-personal-collection-pane", includeMaster: true)
            XCTAssertTrue(text.contains("Choose collections"), text)
            XCTAssertTrue(text.contains("Back"), "The pane's Back label must remain legible: \(text)")
            XCTAssertTrue(text.contains("Funny movies from year 2000"), text)
            XCTAssertTrue(text.contains("Personal collections"), text)
            let rows = self.focusItems(in: window)
            XCTAssertFalse(rows.contains { $0 is UISegmentedControl })
            for row in rows {
                guard let view = row as? UIView else { continue }
                let frame = view.convert(view.bounds, to: window)
                XCTAssertGreaterThanOrEqual(frame.minX, 768, "Controls must stay in the detail pane.")
                XCTAssertLessThanOrEqual(frame.maxX, window.bounds.maxX)
            }
            navigation.pop(animated: false)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(navigation.awaitingFocus)
            let restored = try self.nativeFocusedFrame(system, in: window)
            let rootLabel = try XCTUnwrap(self.collectionLabelFrames(in: window).first { $0.text == "Choose collection" })
            XCTAssertTrue(restored.contains(CGPoint(x: rootLabel.frame.midX, y: rootLabel.frame.midY)),
                          "Back must restore native focus to the parent link.")
        }
    }

    func testCollectionPickerLongLibraryNamesAndEmptySourceStayWithinPane() async throws {
        let provider = HeroPickerHostedProvider(empty: true)
        let account = ResolvedAccount(account: Account(id: "a", from: provider.session), provider: provider)
        let library = AggregatedLibrary(
            accountID: "a", accountName: "Viewer", serverName: "Server",
            providerKind: .silo,
            library: MediaLibrary(id: "movies", title: "Movies with a very long library name that must wrap without clipping", kind: .movie)
        )
        try await withScreen(content: NavigationStack {
            HStack(spacing: 0) {
                Text("Customize Home").frame(width: 768)
                HeroCollectionPickerView(selections: .constant([]), libraries: [library], accounts: [account])
            }
            .ignoresSafeArea()
        }) { window in
            let text = try await self.capture(window, name: "hero-long-source-labels", includeMaster: true)
            XCTAssertTrue(text.contains("without clipping"), text)
            XCTAssertTrue(text.contains("No collections in this source"), text)
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            XCTAssertNotNil(system.focusedItem, "An empty collection list must still offer real focusable controls.")
        }
    }

    private func nativeFocusedFrame(_ system: UIFocusSystem, in window: UIWindow) throws -> CGRect {
        try nativeFrame(XCTUnwrap(system.focusedItem), in: window)
    }

    private func nativeFrame(_ item: any UIFocusItem, in window: UIWindow) throws -> CGRect {
        var environment: (any UIFocusEnvironment)? = item
        while let current = environment {
            if let container = current.focusItemContainer {
                return container.coordinateSpace.convert(item.frame, to: window)
            }
            environment = current.parentFocusEnvironment
        }
        return try XCTUnwrap(Optional<CGRect>.none, "A focused row must expose native focus coordinates.")
    }

    private func collectionLabelFrames(
        in window: UIWindow, attachmentName: String? = nil
    ) throws -> [(text: String, frame: CGRect)] {
        window.layoutIfNeeded()
        let image = renderWindow(window)
        if let attachmentName {
            let attachment = XCTAttachment(image: image)
            attachment.name = attachmentName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { result in
            guard let text = result.topCandidates(1).first?.string else { return nil }
            let bounds = result.boundingBox
            return (text, CGRect(
                x: bounds.minX * window.bounds.width, y: (1 - bounds.maxY) * window.bounds.height,
                width: bounds.width * window.bounds.width, height: bounds.height * window.bounds.height
            ))
        }
    }

    private func assertConcentricGroup(in window: UIWindow, focusFrame: CGRect) throws {
        let image = try XCTUnwrap(renderWindow(window).cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        func brightness(x: Int, y: Int) -> UInt8 { pixels[(y * image.width + x) * 4] }
        let horizontal = Array(Int(focusFrame.minX - 30)...Int(focusFrame.maxX + 30))
        let vertical = Array(Int(focusFrame.minY - 30)...Int(focusFrame.maxY + 30))
        for samples in [
            horizontal.map { brightness(x: $0, y: Int(focusFrame.midY)) },
            vertical.map { brightness(x: Int(focusFrame.midX), y: $0) }
        ] {
            let outerStart = try XCTUnwrap(samples.firstIndex { $0 > 5 })
            let innerStart = try XCTUnwrap(samples.firstIndex { $0 > 240 })
            let outerEnd = try XCTUnwrap(samples.lastIndex { $0 > 5 })
            let innerEnd = try XCTUnwrap(samples.lastIndex { $0 > 240 })
            XCTAssertEqual(CGFloat(innerStart - outerStart), SettingsRowMetrics.formGroupInset, accuracy: 1)
            XCTAssertEqual(CGFloat(outerEnd - innerEnd), SettingsRowMetrics.formGroupInset, accuracy: 1)
        }
    }

    func testFullPageArtworkHighlightsRemainVisibleAtEveryRoundedCorner() throws {
        var hero = HeroSettings.default
        hero.style = .carousel
        for (area, kind) in [
            (ArtworkArea.home, ArtworkScopeDiagram.DetailKind.movie),
            (.details, .movie), (.details, .series)
        ] {
            for palette in [ThemePalette.dark, .light, .pureBlack] {
                for scale in [CGFloat(1), 2] {
                    let renderer = ImageRenderer(content:
                        ArtworkScopeDiagram(area: area, detailKind: kind, heroSettings: hero)
                            .frame(width: 256, height: 144)
                            .environment(\.themePalette, palette)
                    )
                    renderer.scale = scale
                    let image = try XCTUnwrap(renderer.cgImage)
                    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                    try pixels.withUnsafeMutableBytes { bytes in
                        let context = try XCTUnwrap(CGContext(
                            data: bytes.baseAddress, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        ))
                        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    }
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    XCTAssertTrue(UIColor(palette.accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
                    for trailing in [false, true] {
                        for bottom in [false, true] {
                            var accentPixels = 0
                            for y in Int(2 * scale)..<Int(9 * scale) {
                                for x in Int(2 * scale)..<Int(9 * scale) {
                                    let column = trailing ? image.width - 1 - x : x
                                    let row = bottom ? image.height - 1 - y : y
                                    let offset = (row * image.width + column) * 4
                                    if abs(CGFloat(pixels[offset]) - red * 255) < 35,
                                       abs(CGFloat(pixels[offset + 1]) - green * 255) < 35,
                                       abs(CGFloat(pixels[offset + 2]) - blue * 255) < 35,
                                       pixels[offset + 3] > 220 {
                                        accentPixels += 1
                                    }
                                }
                            }
                            XCTAssertGreaterThanOrEqual(
                                accentPixels, Int(3 * scale * scale),
                                "\(area) \(kind), scale=\(scale), trailing=\(trailing), bottom=\(bottom)"
                            )
                        }
                    }
                    let attachment = XCTAttachment(image: UIImage(cgImage: image))
                    attachment.name = "highlight-corners-\(area)-\(kind)-\(scale)-\(palette.isLight)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testCustomizationCardReservesAStableViewportWithoutOverlappingRows() async throws {
        let helpCases: [ViewCustomizationHelp?] = [
            nil,
            ViewCustomizationHelp(detail: try XCTUnwrap(ArtworkArea.home.detail), illustration: .artwork(.home)),
            ViewCustomizationHelp(detail: try XCTUnwrap(ArtworkArea.playback.detail), illustration: .artwork(.playback)),
            ViewCustomizationHelp(detail: try XCTUnwrap(ArtworkArea.details.detail), illustration: .artwork(.details)),
            CardCaptionSettings.default.customizationHelp(in: .home, style: .framed),
            CardCaptionSettings(preference: .hide).customizationHelp(in: .home, style: .borderless)
        ]
        var viewportHeight: CGFloat?
        for (index, help) in helpCases.enumerated() {
            try await withScreen(content: ViewCustomizationList(
                title: "Artwork by view", initialRowID: "viewport-first",
                focusedHelp: { _ in help }
            ) {
                ForEach(0..<18) { index in
                    ViewCustomizationRow(
                        id: index == 0 ? "viewport-first" : "viewport-\(index)",
                        title: "Music", value: "Library", cycle: {}
                    )
                }
            }
            .frame(width: 1100, height: 900)
            .ignoresSafeArea()) { window in
                var views = [try XCTUnwrap(window.rootViewController?.view)]
                var scrollViews: [UIScrollView] = []
                while let view = views.popLast() {
                    if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                        scrollViews.append(scroll)
                    }
                    views.append(contentsOf: view.subviews)
                }
                let scroll = try XCTUnwrap(scrollViews.max { $0.bounds.width < $1.bounds.width })
                if help == nil {
                    XCTAssertEqual(scroll.bounds.height, 900, accuracy: 2,
                                   "Lists without contextual help must not reserve a blank footer.")
                } else {
                    XCTAssertEqual(scroll.bounds.height, 632, accuracy: 2,
                                   "Reserve exactly the card, inset and separation, not an overlay.")
                    if let viewportHeight {
                        XCTAssertEqual(scroll.bounds.height, viewportHeight, accuracy: 1)
                    }
                    viewportHeight = scroll.bounds.height
                    XCTAssertEqual(scroll.adjustedContentInset.bottom, 40, accuracy: 1)
                }
                _ = try await self.capture(window, name: "customization-inset-card-\(index)",
                                           includeMaster: true)
            }
        }
    }

    func testLabelPreviewsOfferRecommendedAndShareCustomizationControls() async throws {
        let suite = "LabelPreviewHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        let settings = Binding(get: { cards.captions }, set: { cards.captions = $0 })
        try await withScreen(content: NavigationStack {
            SettingsSplitLayout(
                title: "Cards",
                rows: [SettingsSplitRow(id: "labels", title: "Labels") {
                    CardLabelControls(settings: settings, style: .borderless)
                }],
                selection: .constant("labels")
            )
        }) { window in
            let initial = try await self.capture(window, name: "labels-recommended-preview")
            for text in [
                "App default", "Show labels everywhere", "Hide labels everywhere",
                "Customize by view"
            ] {
                XCTAssertTrue(initial.contains(text), initial)
            }
            XCTAssertFalse(initial.contains("Showcase"), initial)
            XCTAssertFalse(initial.contains("Plozz chooses"), initial)
            XCTAssertFalse(initial.contains("customizations override"), initial)
            XCTAssertFalse(initial.contains("Using defaults"), initial)
            let previews = self.focusItems(in: window).filter { $0.frame.height > 150 && $0.frame.width > 150 }
            XCTAssertEqual(previews.count, 3)
            let height = try XCTUnwrap(previews.first).frame.height
            for preview in previews {
                XCTAssertEqual(preview.frame.height, height, accuracy: height * 0.02,
                               "Presets must share a height, allowing only native focus scaling.")
            }
            XCTAssertEqual(cards.captions.preference, .recommended)
            cards.captions.setOverride(.hide, for: .browse)
            let customized = try await self.capture(window, name: "labels-customized-preview")
            XCTAssertTrue(customized.split(whereSeparator: \.isWhitespace).contains("Custom"), customized)
            XCTAssertFalse(customized.contains("Remove view customizations"), customized)
            XCTAssertNil(cards.captions.selectedPreset)
        }
    }

    func testContextCardsKeepTheirSentenceReadableAcrossThemesAndTextSizes() async throws {
        let detail = try XCTUnwrap(ArtworkArea.continueWatching.detail)
        for (name, palette) in [("dark", ThemePalette.dark), ("black", .pureBlack), ("light", .light)] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                try await withScreen(content: VStack(spacing: 40) {
                    ViewCustomizationHelpCard(help: .init(
                        detail: detail, illustration: .artwork(.continueWatching)
                    ))
                    Button("Focus target") {}
                }
                .padding(48)
                .frame(width: 1100)
                .background(palette.settingsBackground)
                .environment(\.themePalette, palette)
                .environment(\.colorScheme, palette.isLight ? .light : .dark)
                .environment(\.dynamicTypeSize, size)) { window in
                    let copy = try await self.capture(window, name: "context-card-\(name)-\(size)", includeMaster: true)
                    XCTAssertTrue(copy.contains(String(localized: detail)), copy)
                    XCTAssertEqual(self.focusItems(in: window).count, 1,
                                   "Illustrations and help must remain non-interactive.")
                }
            }
        }
    }

    func testLabelViewChoicesUseShortValuesAndPresetsReplaceCustomizations() async throws {
        let suite = "LabelChoicesHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        let settings = Binding(get: { cards.captions }, set: { cards.captions = $0 })
        try await withScreen(content: CardCaptionCustomizationContent(
            settings: settings
        )) { window in
            let initial = try await self.capture(window, name: "labels-browse-inherited", includeMaster: true)
            XCTAssertTrue(initial.contains("Labels"), initial)
            XCTAssertTrue(initial.contains("Mixed"), initial)
            XCTAssertFalse(initial.contains("Main setting"), initial)
            XCTAssertFalse(initial.contains("App default"), initial)
            XCTAssertFalse(initial.contains("Use default"), initial)
            XCTAssertTrue(initial.uppercased().contains("LIBRARIES"), initial)
            XCTAssertFalse(initial.contains("No labels"), initial)
            var views = [try XCTUnwrap(window.rootViewController?.view)]
            var scrollViews: [UIScrollView] = []
            while let view = views.popLast() {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    scrollViews.append(scroll)
                }
                views.append(contentsOf: view.subviews)
            }
            let scroll = try XCTUnwrap(scrollViews.max { $0.bounds.width < $1.bounds.width })
            let originalOffset = scroll.contentOffset
            // The fixed help card keeps the later section below the initial viewport.
            scroll.setContentOffset(CGPoint(x: originalOffset.x, y: 400), animated: false)
            let laterRows = try await self.capture(window, name: "labels-other-views", includeMaster: true)
            XCTAssertTrue(laterRows.uppercased().contains("OTHER VIEWS"), laterRows)
            scroll.setContentOffset(originalOffset, animated: false)
            cards.captions.toggleCustomization(in: .browse)
            let changed = try await self.capture(window, name: "labels-browse-explicit")
            XCTAssertFalse(changed.contains("Custom"), changed)
            XCTAssertFalse(changed.contains("Use default"), changed)
            XCTAssertEqual(cards.captions.override(for: .browse), .hide)
            XCTAssertFalse(cards.captions.showsLabels(in: .browse))
            XCTAssertEqual(CardCaptionSettingsStore(defaults: defaults).load(), cards.captions)
            cards.captions.applyPreset(.show)
            XCTAssertTrue(cards.captions.showsLabels(in: .browse))
            XCTAssertTrue(cards.captions.overrides.isEmpty)
        }
    }

    func testCardsDetailScrollsThroughWatchedIndicatorsAndTheLastStyleRow() async throws {
        let suite = "CardsViewportHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        let watched = WatchStatusIndicatorSettingsModel(
            store: WatchStatusIndicatorSettingsStore(defaults: defaults)
        )
        try await withScreen(content: SettingsSplitLayout(
            title: "Appearance",
            rows: [SettingsSplitRow(
                id: "cards", title: "Cards",
                description: "How media cards look across the app.",
                subpage: SettingsDetailSubpage { CardCaptionCustomizationView(cards: cards) }
            ) {
                CardAppearanceControls(cards: cards, watchIndicator: watched)
            }]
        )) { window in
            var views = [try XCTUnwrap(window.rootViewController?.view)]
            var scrollViews: [UIScrollView] = []
            while let view = views.popLast() {
                if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    scrollViews.append(scroll)
                }
                views.append(contentsOf: view.subviews)
            }
            let scroll = try XCTUnwrap(scrollViews.max { $0.bounds.width < $1.bounds.width })
            for (offset, words) in [
                (CGFloat(180), ["Watched", "Unwatched"]),
                (scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom,
                 ["Posters", "Cards"])
            ] {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                let copy = try await self.capture(window, name: "cards-viewport-\(Int(offset))")
                for word in words { XCTAssertTrue(copy.contains(word), copy) }
            }
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController as? ArtworkFocusRequesting)
            let target = try XCTUnwrap(self.focusItems(in: window).compactMap { item -> (any UIFocusItem, CGRect)? in
                guard let frame = NavigationRowFocusRequester.frame(of: item, relativeTo: window) else { return nil }
                return frame.minX > window.bounds.width * 0.4 && frame.height > 150 ? (item, frame) : nil
            }.max { $0.1.maxY < $1.1.maxY }?.0)
            host.artworkFocusTarget = target
            system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
            system.updateFocusIfNeeded()
            host.artworkFocusTarget = nil
            let focused = try await self.capture(window, name: "cards-last-style-focused")
            XCTAssertTrue(system.focusedItem === target)
            XCTAssertTrue(focused.contains("Posters") && focused.contains("Cards"), focused)
        }
    }

    func testAppearanceSeparatesArtworkAndGatesHouseholdProviderNavigation() async throws {
        let namespace = "ArtworkAppearanceHosted.\(UUID())"
        let models = ProfileSettingsModel(namespace: namespace)
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(namespace) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        models.cardStyleModel.artwork = .default
        let navigation = SettingsNavigationModel()
        navigation.appearanceRowID = "artwork"
        let libraries = ProfileLibrariesScope(
            accounts: [], activeProfile: .init(id: namespace, name: "Viewer"),
            discoveredLibraries: .empty, refreshingLibraryAccountIDs: [],
            unreachableLibraryAccountIDs: [], reloadLibraries: {},
            homeVisibility: models.homeLibraryVisibilityModel,
            isAccountIncludedInActiveProfile: { _ in false },
            onSetAccountIncluded: { _, _ in }, onAddAccount: {},
            plexHomeUsersFetcher: { _ in [] }, onSelectPlexHomeUser: { _, _ in }
        )
        for canManage in [true, false] {
            let content = NavigationStack {
                AppearanceDetailView(
                    librariesScope: libraries, settingsNavigation: navigation,
                    canManageProviders: canManage,
                    theme: models.themeModel, nightShift: models.nightShiftModel,
                    spoilers: models.spoilerModel
                )
            }
            .environment(models.musicPlayerModel)
            .environment(models.uiDensityModel)
            .environment(models.cardStyleModel)
            .environment(models.watchStatusIndicatorModel)
            .environment(models.navigationStyleModel)
            .environment(models.transparencyModel)
            .environment(models.appLanguageModel)
            try await withScreen(content: content) { window in
                let text = try await self.capture(window, name: "artwork-appearance-providers-\(canManage)")
                XCTAssertTrue(text.contains("Choose the posters, backgrounds, and logos you see"), text)
                XCTAssertTrue(text.contains("Recommended"), text)
                XCTAssertTrue(text.contains("Prefer my library"), text)
                XCTAssertTrue(text.contains("Prefer artwork from metadata providers"), text)
                XCTAssertTrue(text.contains("Customize by view"), text)
                XCTAssertFalse(text.contains("Using defaults"), text)
                XCTAssertFalse(text.contains("About artwork sources"), text)
                XCTAssertFalse(text.contains("Remove view customizations"), text)
                XCTAssertEqual(text.contains("Metadata Providers"), canManage, text)
                XCTAssertEqual(text.contains("TMDB"), canManage, text)
                XCTAssertEqual(text.contains("TheTVDB"), canManage, text)
                XCTAssertFalse(text.contains("Online services"), text)
                if canManage {
                    models.cardStyleModel.artwork.setOverride(.library, for: .browse)
                    let customized = try await self.capture(window, name: "artwork-appearance-customized")
                    XCTAssertTrue(customized.split(whereSeparator: \.isWhitespace).contains("Custom"), customized)
                    XCTAssertFalse(customized.contains("Remove view customizations"), customized)
                    models.cardStyleModel.artwork.resetOverrides()
                }
            }
        }
    }

    func testBrowseShowsOnlyItsSourceAndPresetChangesReplaceExplicitChoices() async throws {
        let suite = "ArtworkSettingsHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        try await withScreen(cards: cards, area: .browse) { window in
            let inherited = try await self.capture(window, name: "artwork-browse-use-preset")
            XCTAssertTrue(inherited.contains("Library"), inherited)
            XCTAssertFalse(inherited.contains("Main setting"), inherited)
            XCTAssertFalse(inherited.contains("Recommended"), inherited)
            XCTAssertFalse(inherited.contains("Use default"), inherited)
            XCTAssertFalse(inherited.contains("without text"), inherited)
            XCTAssertFalse(inherited.contains("Continue Watching"), inherited)
            XCTAssertLessThan(inherited.split(whereSeparator: \.isWhitespace).count, 8, inherited)

            cards.artwork.setOverride(.online, for: .browse)
            let overridden = try await self.capture(window, name: "artwork-browse-provider-first")
            XCTAssertTrue(overridden.contains("Metadata providers"), overridden)
            XCTAssertFalse(overridden.contains("Custom"), overridden)
            XCTAssertEqual(cards.artwork.override(for: .browse), .online)
            cards.artwork.applyPreset(.library)
            let changed = try await self.capture(window, name: "artwork-browse-changed-preset")
            XCTAssertTrue(changed.contains("Library"), changed)
            XCTAssertFalse(changed.contains("Custom"), changed)
            XCTAssertEqual(cards.artwork.selectedPreset, .library)
            XCTAssertTrue(cards.artwork.overrides.isEmpty)
            XCTAssertEqual(ArtworkSettingsStore(defaults: defaults).load(), cards.artwork)
        }
    }

    func testContinueWatchingShowsOnlyItsResolvedSource() async throws {
        let suite = "ArtworkContinueWatchingHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        try await withScreen(cards: cards, area: .continueWatching) { window in
            let text = try await self.capture(window, name: "artwork-continue-watching")
            XCTAssertTrue(text.contains("Metadata providers"), text)
            XCTAssertFalse(text.contains("Main setting"), text)
            XCTAssertFalse(text.contains("Recommended"), text)
            XCTAssertFalse(text.contains("Custom"), text)
            XCTAssertTrue(cards.artwork.prefersTextlessArtwork(in: .continueWatching))
            let row = try XCTUnwrap(self.focusItems(in: window).first { $0.frame.width > 700 })
            XCTAssertLessThan(row.frame.height, 80, "The name and value must fit one line at normal TV text size.")
        }
    }

    func testMixedChoicesCycleBackOnTVWithoutChangingOtherViews() async throws {
        let suite = "MixedChoicesHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        cards.artwork = ArtworkSettings(preference: .library)
        try await withScreen(cards: cards, area: .details) { window in
            for value in ["Library", "Metadata providers", "Mixed", "Library"] {
                let text = try await self.capture(window, name: "artwork-details-cycle-\(value)")
                XCTAssertTrue(text.contains(value), text)
                XCTAssertFalse(text.contains("Use default"), text)
                XCTAssertEqual(cards.artwork.preference(in: .browse), .library)
                XCTAssertEqual(ArtworkSettingsStore(defaults: defaults).load(), cards.artwork)
                cards.artwork.toggleCustomization(in: .details)
            }
        }
        cards.captions = CardCaptionSettings(preference: .hide)
        try await withScreen(content: SettingsSplitLayout(
            title: "Cards",
            rows: [SettingsSplitRow(id: "labels", title: "Labels") {
                CardCaptionViewChoices(view: .home, settings: Binding(
                    get: { cards.captions }, set: { cards.captions = $0 }
                ))
            }]
        )) { window in
            for value in ["Off", "Mixed", "On", "Off"] {
                let text = try await self.capture(window, name: "labels-home-cycle-\(value)")
                XCTAssertTrue(text.contains(value), text)
                XCTAssertFalse(text.contains("Use default"), text)
                XCTAssertFalse(cards.captions.showsLabels(in: .browse))
                XCTAssertEqual(CardCaptionSettingsStore(defaults: defaults).load(), cards.captions)
                cards.captions.toggleCustomization(in: .home)
            }
        }
    }

    func testPresetExplanationsFollowNativeFocusWithoutChangingSelection() async throws {
        let suite = "ArtworkFocusHosted.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = makeCards(defaults: defaults)
        try await withScreen(content: NavigationStack {
            SettingsSplitLayout(
                title: "Appearance",
                rows: [SettingsSplitRow(id: "artwork", title: "Artwork") {
                    ArtworkSettingsControls(cards: cards)
                }],
                selection: .constant("artwork")
            )
        }) { window in
            let snippets = [
                "Plozz chooses artwork to suit each part",
                "Always use local artwork from your libraries",
                "Always use metadata-provider artwork"
            ]
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController as? ArtworkFocusRequesting)
            for index in 0..<4 {
                window.layoutIfNeeded()
                let allItems = self.focusItems(in: window)
                let items = allItems.filter { $0.frame.width > 700 }
                    .sorted { $0.frame.minY < $1.frame.minY }
                XCTAssertEqual(items.count, 4, allItems.map { "\($0.frame)" }.joined(separator: ", "))
                let target = try XCTUnwrap(items.indices.contains(index) ? items[index] : nil)
                host.artworkFocusTarget = target
                system.requestFocusUpdate(to: try XCTUnwrap(window.rootViewController))
                system.updateFocusIfNeeded()
                host.artworkFocusTarget = nil
                let text = try await self.capture(window, name: "artwork-preset-focus-\(index)")
                XCTAssertTrue(system.focusedItem === target, "Inline help must retain native focus.")
                for (snippetIndex, snippet) in snippets.enumerated() {
                    XCTAssertEqual(text.contains(snippet), index == snippetIndex, text)
                }
                XCTAssertEqual(cards.artwork.preference, .recommended, "Focus must not select a preference.")
                XCTAssertFalse(text.contains("About artwork sources"), text)
            }
        }
    }

    private func focusItems(in window: UIWindow) -> [any UIFocusItem] {
        var containers: [any UIFocusItemContainer] = [window]
        var seen = Set<ObjectIdentifier>()
        var items: [ObjectIdentifier: any UIFocusItem] = [:]
        while let container = containers.popLast() {
            guard seen.insert(ObjectIdentifier(container)).inserted else { continue }
            let frame = container.coordinateSpace.convert(window.bounds, from: window)
            for item in container.focusItems(in: frame) {
                if let child = item.focusItemContainer { containers.append(child) }
                if let view = item as? UIView { containers.append(view) }
                if item.canBecomeFocused, !(item is UIScrollView) {
                    items[ObjectIdentifier(item)] = item
                }
            }
        }
        return Array(items.values)
    }

    private func verticalScroll(in window: UIWindow) throws -> UIScrollView {
        var pending = [try XCTUnwrap(window.rootViewController?.view)]
        var scrolls: [UIScrollView] = []
        while let view = pending.popLast() {
            if let scroll = view as? UIScrollView {
                scrolls.append(scroll)
            }
            pending.append(contentsOf: view.subviews)
        }
        return try XCTUnwrap(scrolls.max { $0.bounds.width < $1.bounds.width })
    }

    private func makeCards(defaults: UserDefaults) -> CardStyleSettingsModel {
        CardStyleSettingsModel(
            store: CardStyleSettingsStore(defaults: defaults),
            focusStore: CardFocusStyleSettingsStore(defaults: defaults),
            captionStore: CardCaptionSettingsStore(defaults: defaults),
            artworkStore: ArtworkSettingsStore(defaults: defaults)
        )
    }

    private func withScreen(
        cards: CardStyleSettingsModel,
        area: ArtworkArea,
        inspect: (UIWindow) async throws -> Void
    ) async throws {
        try await withScreen(
            content: SettingsSplitLayout(
                title: "Appearance",
                rows: [SettingsSplitRow(id: "artwork", title: "Artwork") {
                    ArtworkAreaChoices(area: area, settings: Binding(
                        get: { cards.artwork }, set: { cards.artwork = $0 }
                    ))
                }]
            ),
            inspect: inspect
        )
    }

    private func withScreen(
        content: some View,
        topSafeArea: CGFloat = 0,
        bottomSafeArea: CGFloat = 0,
        inspect: (UIWindow) async throws -> Void
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
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.overrideUserInterfaceStyle = .dark
        let host = ArtworkFocusHost(rootView:
            content
                .environment(\.themePalette, .dark)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US"))
        )
        host.additionalSafeAreaInsets.top = topSafeArea
        host.additionalSafeAreaInsets.bottom = bottomSafeArea
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }

        let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
        let focusDeadline = ContinuousClock.now + .seconds(3)
        while system.focusedItem == nil, ContinuousClock.now < focusDeadline {
            window.layoutIfNeeded()
            system.requestFocusUpdate(to: host)
            system.updateFocusIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(system.focusedItem)
        try await Task.sleep(for: .milliseconds(350))
        try await inspect(window)
    }

    private func renderWindow(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            UIColor.black.setFill()
            context.fill(window.bounds)
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func capture(_ window: UIWindow, name: String, includeMaster: Bool = false) async throws -> String {
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
        let image = renderWindow(window)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        if !includeMaster {
            request.regionOfInterest = CGRect(x: 0.40, y: 0, width: 0.60, height: 1)
        }
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}

@MainActor
private protocol ArtworkFocusRequesting: AnyObject {
    var artworkFocusTarget: (any UIFocusEnvironment)? { get set }
}

private struct HeroPickerHostedProvider: MediaProvider, CapabilityReporting {
    let empty: Bool
    var collectionCount = 1
    let kind: ProviderKind = .silo
    let session = UserSession(
        server: MediaServer(id: "server", name: "Server", baseURL: URL(string: "https://example.com")!, provider: .silo),
        userID: "viewer", userName: "Viewer", deviceID: "device", accessToken: "fixture"
    )
    var capabilities: ProviderCapability { [.personalCollections, .libraryCollections] }
    func collections(in libraryID: String, page: PageRequest) async throws -> MediaPage {
        .init(items: empty ? [] : [
            .init(id: "\(libraryID)-collection", title: "\(libraryID) picks", kind: .collection)
        ], startIndex: 0, totalCount: empty ? 0 : 1)
    }
    func personalCollections(page: PageRequest) async throws -> MediaPage {
        let items: [MediaItem] = empty ? [] : (0..<collectionCount).map {
            .init(
                id: $0 == 0 ? "personal" : "personal-\($0)",
                title: $0 == 0 ? "Funny movies from year 2000+" : "Collection \($0 + 1)",
                kind: .collection
            )
        }
        return .init(items: Array(items.dropFirst(page.startIndex).prefix(page.limit)),
                     startIndex: page.startIndex, totalCount: items.count)
    }
    func libraries() async throws -> [MediaLibrary] { [] }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage { throw AppError.notFound }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}

@MainActor
private final class ArtworkFocusHost<Content: View>: UIHostingController<Content>, ArtworkFocusRequesting {
    weak var artworkFocusTarget: (any UIFocusEnvironment)?

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        artworkFocusTarget.map { [$0] } ?? super.preferredFocusEnvironments
    }
}
