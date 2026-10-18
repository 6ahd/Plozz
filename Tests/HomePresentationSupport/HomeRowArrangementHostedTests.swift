import CoreModels
import CoreUI
#if os(tvOS)
@testable import FeatureHome
#elseif os(iOS)
@testable import AppShelliOS
#endif
@testable import FeatureSettings
import Observation
import SwiftUI
import UIKit
import Vision
import XCTest

@MainActor
final class HomeRowArrangementHostedTests: XCTestCase {
    func testPresetPageRefreshesRecoveredNativeSectionsBeforeSavingCustomRows() async throws {
        let suite = "HomePresetRecovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        let provider = HomeSettingsLibraryProvider(
            name: "Recovered server", homeError: .serverUnreachable, kind: .plex,
            homeLayout: .init(sections: [.init(id: "native", kind: .recommendations)], source: .promotedHubs)
        )
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        await inventory.load(libraries: [], accounts: [account], visibility: visibility)
        XCTAssertEqual(inventory.serverFailures[account.account.id], .serverUnreachable)

        try await withWindow {
            HomeRowPresetsView(inventory: inventory, visibility: visibility, libraries: [], accounts: [account])
        } inspect: { window in
            _ = try await self.capture(window, name: "Preset before server recovery")
            await provider.setHomeError(nil)
            visibility.useRowDefaults(.matchServer)
            let native = HomeRowID.server(accountID: account.account.id, section: "native")
            let recovered = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    !inventory.isLoading && inventory.serverFailures.isEmpty
                        && inventory.catalog.sections(in: visibility.visibility).enabled == [native]
                }, object: nil
            )
            await self.fulfillment(of: [recovered], timeout: 5)
            try visibility.setHomeSectionVisible(true, id: .libraries, catalog: inventory.catalog)
            XCTAssertEqual(inventory.catalog.sections(in: visibility.visibility).enabled, [native, .libraries])
            _ = try await self.capture(window, name: "Preset after server recovery")
        }
    }

    #if os(iOS)
    func testPushingAddSectionFinishesDiscoveryAfterTheRootDisappears() async throws {
        let suite = "HomeAddDiscovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(store: HomeLibraryVisibilityStore(defaults: defaults))
        visibility.useRowDefaults(.combined)
        let requested = expectation(description: "Root starts a held native-section request")
        let provider = HomeSettingsLibraryProvider(
            name: "Slow server", kind: .plex,
            homeLayout: .init(
                sections: [.init(id: "native", kind: .recommendations, title: "Native picks")], source: .promotedHubs
            ),
            holdsHome: true, onFirstHomeRequest: { requested.fulfill() }
        )
        let account = ResolvedAccount(account: Account(from: provider.session), provider: provider)
        let inventory = HomeSectionCatalogModel()
        let navigation = HomeCatalogNavigationFixture()
        try await withWindow {
            HomeCatalogNavigationHost(navigation: navigation, inventory: inventory, visibility: visibility, accounts: [account])
        } inspect: { window in
            await self.fulfillment(of: [requested], timeout: 5)
            XCTAssertTrue(inventory.isLoading)
            navigation.path = ["add"]
            let pushed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in navigation.rootDisappeared && navigation.addAppeared }, object: nil
            )
            await self.fulfillment(of: [pushed], timeout: 5)
            await provider.resumeHome()
            let native = HomeRowID.server(accountID: account.account.id, section: "native")
            let discovered = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    !inventory.isLoading && inventory.catalog.sections(in: visibility.visibility).disabled.contains(native)
                }, object: nil
            )
            await self.fulfillment(of: [discovered], timeout: 5)
            let lines = try await self.capture(window, name: "Native section discovered on Add section")
            XCTAssertTrue(lines.contains { $0.0.contains("Native picks") }, lines.map(\.0).joined(separator: " "))
            try visibility.setHomeSectionVisible(true, id: native, catalog: inventory.catalog)
            navigation.path = []
            let returned = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in !navigation.addAppeared }, object: nil
            )
            await self.fulfillment(of: [returned], timeout: 5)
            XCTAssertTrue(inventory.catalog.sections(in: visibility.visibility).enabled.contains(native))
        }
        await provider.resumeHome()
    }
    #endif

    func testMergeNextUpControlIsReadableAndReflectsHiddenContinueWatching() async throws {
        let suite = "HomeNextUpControl.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        for scheme: ColorScheme in [.light, .dark] {
            for size: DynamicTypeSize in [.large, .accessibility3] {
                visibility.setGlobalRowEnabled(true, for: .continueWatching)
                try await withWindow {
                    ScrollView {
                        ContinueWatchingNextUpControl(visibility: visibility)
                            .padding(32)
                    }
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.themePalette, scheme == .light ? ThemePalette.light : .dark)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .light ? Color.white : Color.black)
                    #if os(tvOS)
                    .frame(width: 900, height: 650)
                    #endif
                } inspect: { window in
                    let lines = try await self.capture(window, name: "Merge Next Up \(scheme) \(size)")
                    let text = lines.map(\.0).joined(separator: " ")
                    XCTAssertTrue(text.contains("Merge Next Up rows"), text)
                    XCTAssertTrue(text.contains("next episodes"), text)
                    visibility.setGlobalRowEnabled(false, for: .continueWatching)
                    let disabled = try await self.capture(window, name: "Merge Next Up with hidden Continue Watching")
                    XCTAssertTrue(disabled.map(\.0).joined(separator: " ").contains("Add Continue Watching"), text)
                }
            }
        }
    }

    #if os(iOS)
    func testMobileCustomizeHomeListsSectionsWithoutDetachedArtworkOrMergeControls() async throws {
        let suite = "MobileHomeNextUp.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        visibility.useRowDefaults(.combined)
        visibility.setMergeNextUpIntoContinueWatching(true)
        try await withWindow {
            NavigationStack {
                PlozziOSHomeSettingsView(
                    hero: HeroSettingsModel(store: InMemoryHeroSettingsStore()),
                    heroBackground: HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()),
                    visibility: visibility, accounts: []
                )
            }
        } inspect: { window in
            let lines = try await self.capture(window, name: "Mobile Home artwork without duplicate merge toggle")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Reorder"), text)
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertTrue(text.contains("Continue Watching"), text)
            XCTAssertFalse(text.contains("Artwork"), text)
            XCTAssertFalse(text.contains("Merge Next Up rows"), text)
            XCTAssertFalse(text.contains("No video libraries are available"), text)
            XCTAssertTrue(store.load().mergeNextUpIntoContinueWatching)

            visibility.setGlobalRowEnabled(false, for: .continueWatching)
            let hidden = try await self.capture(window, name: "Mobile Home with Continue Watching hidden")
            let hiddenText = hidden.map(\.0).joined(separator: " ")
            XCTAssertFalse(hiddenText.contains("Artwork"), hiddenText)
            XCTAssertFalse(hiddenText.contains("CONTINUE WATCHING"), "Do not leave an empty section for a hidden row.")
            XCTAssertFalse(hiddenText.contains("Merge Next Up rows"), hiddenText)
            XCTAssertTrue(store.load().mergeNextUpIntoContinueWatching)
        }
    }

    func testMobileSectionMergeSwitchPersistsWithoutChangingPreset() async throws {
        let suite = "MobileHomeRowsNextUp.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        visibility.useRowDefaults(.combined)
        try await withWindow {
            NavigationStack {
                HomeSectionSettingsView(
                    choice: HomeRowChoice.shared.first { $0.id == .global(.continueWatching) }!,
                    inventory: HomeSectionCatalogModel(), visibility: visibility, libraries: [], accounts: []
                )
            }
        } inspect: { window in
            _ = try await self.capture(window, name: "Mobile Rows on Home merge setting")
            func switches(_ view: UIView) -> [UISwitch] {
                (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches)
            }
            let control = try XCTUnwrap(switches(window).first)
            XCTAssertFalse(control.isOn)
            control.setOn(true, animated: false)
            control.sendActions(for: .valueChanged)
            let lines = try await self.capture(window, name: "Mobile Rows on Home with Next Up merged")
            XCTAssertTrue(store.load().mergeNextUpIntoContinueWatching)
            XCTAssertEqual(visibility.visibility.rowCustomization?.defaults, .combined)
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Continue Watching"), text)
            XCTAssertTrue(text.contains("Merge Next Up rows"), text)
        }
    }

    func testNativeReorderPreviewHasRoundedCorners() async throws {
        try await withWindow {
            LiftableReorderList(
                sections: .init(enabled: ["Alpha", "Beta"], disabled: []),
                disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                isLifting: .constant(false),
                row: { .init(title: Text(verbatim: $0), subtitle: Text("Movies")) },
                onChange: { _ in }
            )
            .padding(24)
        } inspect: { window in
            _ = try await self.capture(window, name: "Native reorder rows")
            var views: [UIView] = [window]
            var collection: UICollectionView?
            while let view = views.popLast() {
                if let list = view as? UICollectionView {
                    collection = list
                    break
                }
                views += view.subviews
            }
            let list = try XCTUnwrap(collection)
            let index = IndexPath(item: 0, section: 0)
            let parameters = try XCTUnwrap(
                list.dragDelegate?.collectionView?(list, dragPreviewParametersForItemAt: index)
            )
            let path = try XCTUnwrap(parameters.visiblePath)
            let bounds = path.bounds
            XCTAssertGreaterThan(bounds.width, 200)
            XCTAssertGreaterThan(bounds.height, 40)
            XCTAssertTrue(path.contains(CGPoint(x: bounds.midX, y: bounds.midY)))
            for x in [bounds.minX + 1, bounds.maxX - 1] {
                for y in [bounds.minY + 1, bounds.maxY - 1] {
                    XCTAssertFalse(path.contains(CGPoint(x: x, y: y)), "Drag previews must cut out each corner.")
                }
            }
        }
    }

    func testOfflineServerDoesNotAddAGlobalWarningToHomeCustomization() async throws {
        let suite = "HomeSettingsOffline.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let offline = HomeSettingsLibraryProvider(name: "Offline server", isOffline: true)
        let online = HomeSettingsLibraryProvider(name: "Available server", isOffline: false)
        visibility.applyRows(
            .init(enabled: [.global(.continueWatching)], disabled: [.global(.watchlist)]),
            choices: HomeRowChoice.shared
        )
        let saved = store.load()
        try await withWindow {
            NavigationStack {
                PlozziOSHomeSettingsView(
                    hero: HeroSettingsModel(store: InMemoryHeroSettingsStore()),
                    heroBackground: HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()),
                    visibility: visibility,
                    accounts: [offline, online].map {
                        ResolvedAccount(account: Account(from: $0.session), provider: $0)
                    }
                )
            }
        } inspect: { window in
            let deadline = ContinuousClock.now + .seconds(3)
            while await online.libraryRequests == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let offlineRequests = await offline.libraryRequests
            XCTAssertEqual(offlineRequests, 1)
            let lines = try await self.capture(window, name: "Home customization with an offline server")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Reorder"), text)
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertFalse(text.contains("Available server"), "Whole-library controls belong in Settings > Libraries.")
            XCTAssertFalse(text.contains("Movies"), text)
            XCTAssertFalse(text.contains("LIBRARIES"), text)
            XCTAssertFalse(text.contains("Some libraries are"), text)
            XCTAssertFalse(text.contains("Retry"), text)
            XCTAssertEqual(store.load(), saved)
        }
    }

    func testLibraryDiscoveryRefreshesForEffectiveCredentialsAndPlexViewerChanges() async throws {
        let suite = "HomeSettingsViewer.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let first = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Original movies", kind: .plex)
        let rotated = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Updated movies", kind: .plex)
        let child = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Child movies", kind: .plex)
        let account = Account(from: first.session)
        let revision = CredentialRevision()
        let updates: [(ResolvedAccount, HomeSettingsLibraryProvider, String)] = [
            (.init(account: account, provider: first, plexHomeUserID: "owner"), first, "Original movies"),
            (.init(account: account, provider: rotated, plexHomeUserID: "owner",
                   credentialRevision: revision), rotated, "Updated movies"),
            (.init(account: account, provider: child, plexHomeUserID: "child",
                   credentialRevision: revision), child, "Child movies")
        ]
        let source = HomeSettingsAccountsFixture(accounts: [updates[0].0])
        try await withWindow {
            HomeSettingsViewerHost(source: source, visibility: visibility)
        } inspect: { window in
            for (resolved, provider, title) in updates {
                source.accounts = [resolved]
                let deadline = ContinuousClock.now + .seconds(3)
                while await provider.libraryRequests == 0, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                let requests = await provider.libraryRequests
                XCTAssertEqual(requests, 1, title)
                let lines = try await self.capture(window, name: "Home settings \(title)")
                let text = lines.map(\.0).joined(separator: " ")
                XCTAssertTrue(text.contains("Reorder"), text)
                XCTAssertTrue(text.contains("Hero"), text)
                XCTAssertTrue(text.contains(title), "Expected the active viewer's \(title): \(text)")
            }
        }
    }

    func testLateLibraryFailureDoesNotRestoreRemovedLibraryManagementUI() async throws {
        let suite = "HomeSettingsLateFailure.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let first = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Original movies")
        let delayed = HomeSettingsLibraryProvider(name: "Offline", isOffline: true, holdsLibraries: true)
        let current = HomeSettingsLibraryProvider(name: "Server", libraryTitle: "Current movies")
        defer { Task { await delayed.resumeLibraries() } }
        let account = Account(from: first.session)
        let source = HomeSettingsAccountsFixture(accounts: [
            .init(account: account, provider: first),
            .init(account: Account(from: delayed.session), provider: delayed)
        ])
        try await withWindow {
            HomeSettingsViewerHost(source: source, visibility: visibility)
        } inspect: { window in
            let deadline = ContinuousClock.now + .seconds(3)
            while await delayed.libraryRequests == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let delayedRequests = await delayed.libraryRequests
            XCTAssertEqual(delayedRequests, 1)
            source.accounts = [.init(account: account, provider: current)]
            let currentDeadline = ContinuousClock.now + .seconds(3)
            while await current.libraryRequests == 0, ContinuousClock.now < currentDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            let currentRequests = await current.libraryRequests
            XCTAssertEqual(currentRequests, 1)
            let before = try await self.capture(window, name: "Current account libraries")
            XCTAssertTrue(before.map(\.0).joined(separator: " ").contains("Reorder"))
            await delayed.resumeLibraries()
            let after = try await self.capture(window, name: "Current libraries after stale failure")
            let text = after.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Hero"), text)
            XCTAssertTrue(text.contains("Current movies"), text)
            XCTAssertFalse(text.contains("Original movies"), text)
        }
    }
    #endif

    func testMatchServerNamesEachFailedServerWithoutCallingOtherErrorsOffline() async throws {
        let suite = "HomeRowServerFailures.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        let offline = HomeSettingsLibraryProvider(name: "Basement", homeError: .serverUnreachable)
        let unauthorized = HomeSettingsLibraryProvider(name: "Cinema", homeError: .unauthorized)
        let invalid = HomeSettingsLibraryProvider(name: "Loft", homeError: .invalidResponse)
        let online = HomeSettingsLibraryProvider(name: "Available server")
        let accounts = [offline, unauthorized, invalid, online].map {
            ResolvedAccount(account: Account(from: $0.session), provider: $0)
        }
        await visibility.prepareServerDefaults(accounts: accounts)
        XCTAssertEqual(visibility.serverMatchFailures.count, 3)
        let inventory = HomeSectionCatalogModel()
        await inventory.load(libraries: [], accounts: accounts, visibility: visibility)

        try await withWindow {
            ScrollView {
                HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: [], retry: {})
                    .padding(24)
            }
            #if os(tvOS)
            .frame(width: 1050)
            #endif
        } inspect: { window in
            let lines = try await self.capture(window, name: "Named Home server failures")
            let text = lines.map(\.0).joined(separator: " ")
            XCTAssertTrue(text.contains("Basement is offline."), text)
            XCTAssertTrue(text.contains("Sign in to Cinema again."), text)
            XCTAssertTrue(text.contains("load sections from Loft."), text)
            XCTAssertFalse(text.contains("Cinema is offline"), text)
            XCTAssertFalse(text.contains("Loft is offline"), text)
            XCTAssertFalse(text.contains("Available server is offline"), text)
            XCTAssertFalse(text.contains("server arrangements"), text)
            XCTAssertFalse(text.contains("Keeping known rows"), text)

            await offline.setHomeError(nil)
            await inventory.load(libraries: [], accounts: accounts, visibility: visibility)
            let recovered = try await self.capture(window, name: "Recovered Home server")
            let recoveredText = recovered.map(\.0).joined(separator: " ")
            XCTAssertFalse(recoveredText.contains("Basement is offline"), recoveredText)
            XCTAssertTrue(recoveredText.contains("Sign in to Cinema again."), recoveredText)
            XCTAssertTrue(recoveredText.contains("load sections from Loft."), recoveredText)
        }
    }

    func testSharedArrangerReflectsCrossLibraryOrderAndPersistsEdits() async throws {
        let suite = "HomeRowArrangement.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        let visibility = HomeLibraryVisibilityModel(store: store)
        let accounts = ["Alpha", "Beta"].map { name in
            let provider = HomeSettingsLibraryProvider(name: name, kind: .mediaShare)
            return ResolvedAccount(account: Account(from: provider.session), provider: provider)
        }
        let libraries = accounts.map {
            AggregatedLibrary(
                accountID: $0.account.id, accountName: "Viewer", serverName: "Server",
                providerKind: .mediaShare,
                library: MediaLibrary(id: $0.account.server.name, title: "\($0.account.server.name) Movies", kind: .movie)
            )
        }

        let choices = libraries.flatMap(HomeRowChoice.baseRows) + HomeRowChoice.shared
        let ids: [HomeRowID] = [
            .global(.continueWatching), .library(libraries[0].key, kind: .recentlyAdded),
            .global(.watchlist), .library(libraries[1].key, kind: .recentlyAdded)
        ]
        let hidden = HomeRowChoice.shared.map(\.id).filter { !ids.contains($0) }
        visibility.applyRows(.init(enabled: ids, disabled: hidden), choices: choices)

        try await withWindow {
            #if os(iOS)
            NavigationStack {
                HomeRowsSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
            }
            #else
            HomeRowsSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
            .frame(width: 1050)
            #endif
        } inspect: { window in
            let before = try await self.capture(window, name: "Home arranger original order")
            XCTAssertFalse(before.contains { $0.0.contains("Merge Next Up rows") })
            XCTAssertTrue(before.contains { $0.0.contains("Hero") })
            XCTAssertGreaterThan(try self.y("Alpha", in: before), try self.y("Beta", in: before))
            XCTAssertTrue(before.contains { $0.0.contains("All libraries") })
            visibility.applyRows(.init(enabled: Array(ids.reversed()), disabled: hidden), choices: choices)
            let after = try await self.capture(window, name: "Home arranger reversed order")
            XCTAssertGreaterThan(try self.y("Beta", in: after), try self.y("Alpha", in: after))
            XCTAssertEqual(store.load().rowSections(choices: choices).enabled, Array(ids.reversed()))
        }
    }

    func testRowSubtitlesAndRanksRemainVisibleAtLargeTextSizes() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await withWindow {
                ScrollView {
                    LiftableReorderList(
                        sections: .init(enabled: ["Alpha", "Beta"], disabled: []),
                        disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                        isLifting: .constant(false),
                        row: {
                            .init(title: Text(verbatim: $0), subtitle: Text("Movies"))
                        }, onChange: { _ in }
                    )
                    .padding(30)
                }
                .environment(\.dynamicTypeSize, size)
                #if os(tvOS)
                .frame(width: 1050)
                #endif
            } inspect: { window in
                let text = try await self.capture(window, name: "Home row text size \(size)")
                XCTAssertGreaterThan(try self.y("Alpha", in: text), try self.y("Beta", in: text))
                XCTAssertEqual(text.filter { $0.0.contains("Movies") }.count, 2)
            }
        }
    }

    func testPresetActionsRemainSeparatedAtLargeTextSizes() async throws {
        let suite = "HomeRowPresets.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = HomeLibraryVisibilityModel(
            store: HomeLibraryVisibilityStore(defaults: defaults, namespace: "viewer")
        )
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await withWindow {
                HomeRowPresetsView(
                    inventory: HomeSectionCatalogModel(), visibility: visibility, libraries: [], accounts: []
                )
                .environment(\.dynamicTypeSize, size)
                #if os(tvOS)
                .frame(width: 1050)
                #endif
            } inspect: { window in
                let lines = try await self.capture(window, name: "Home presets text size \(size)")
                let text = lines.map(\.0).joined(separator: " ").replacingOccurrences(of: "- ", with: "-")
                XCTAssertTrue(text.contains("Match server"), text)
                XCTAssertTrue(text.contains("Combined rows"), text)
                XCTAssertGreaterThan(
                    try self.y("Match server", in: lines),
                    try self.y("Combined rows", in: lines)
                )
            }
        }
    }

    #if os(tvOS)
    func testAllHiddenNoticeStillProvidesANativeFocusTarget() async throws {
        try await withWindow {
            HomeContentNoticeView(notice: .noHomeRows, onReload: {})
        } inspect: { window in
            let system = try XCTUnwrap(UIFocusSystem.focusSystem(for: window))
            let host = try XCTUnwrap(window.rootViewController)
            let deadline = ContinuousClock.now + .seconds(3)
            while system.focusedItem == nil, ContinuousClock.now < deadline {
                window.layoutIfNeeded()
                system.requestFocusUpdate(to: host)
                system.updateFocusIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotNil(system.focusedItem)
            let text = try await self.capture(window, name: "All Home rows hidden")
            XCTAssertTrue(text.contains { $0.0.contains("Reload") })
        }
    }
    #endif

    private func withWindow<Content: View>(
        @ViewBuilder content: () -> Content,
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
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView:
            content()
                .environment(HeroSettingsModel(store: InMemoryHeroSettingsStore()))
                .environment(HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore()))
                .environment(\.themePalette, ThemePalette.dark)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: "en_US"))
                .background(.black)
        )
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        try await inspect(window)
    }

    private func capture(_ window: UIWindow, name: String) async throws -> [(String, CGRect)] {
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return (request.results ?? []).compactMap { result in
            result.topCandidates(1).first.map { ($0.string, result.boundingBox) }
        }
    }

    private func y(_ name: String, in lines: [(String, CGRect)]) throws -> CGFloat {
        try XCTUnwrap(lines.first { $0.0.contains(name) }, lines.map(\.0).joined(separator: " | ")).1.midY
    }
}

#if os(iOS)
@MainActor @Observable
private final class HomeCatalogNavigationFixture {
    var path: [String] = []
    var rootDisappeared = false
    var addAppeared = false
}

@MainActor
private struct HomeCatalogNavigationHost: View {
    @Bindable var navigation: HomeCatalogNavigationFixture
    let inventory: HomeSectionCatalogModel
    let visibility: HomeLibraryVisibilityModel
    let accounts: [ResolvedAccount]

    var body: some View {
        NavigationStack(path: $navigation.path) {
            HomeRowsSettingsView(libraries: [], accounts: accounts, visibility: visibility, inventory: inventory)
                .onDisappear { navigation.rootDisappeared = true }
                .navigationDestination(for: String.self) { _ in
                    HomeAddSectionView(inventory: inventory, visibility: visibility, libraries: [], accounts: accounts)
                        .onAppear { navigation.addAppeared = true }
                        .onDisappear { navigation.addAppeared = false }
                }
        }
    }
}

@MainActor @Observable
private final class HomeSettingsAccountsFixture {
    var accounts: [ResolvedAccount]
    init(accounts: [ResolvedAccount]) { self.accounts = accounts }
}

@MainActor
private struct HomeSettingsViewerHost: View {
    let source: HomeSettingsAccountsFixture
    let visibility: HomeLibraryVisibilityModel
    private let hero = HeroSettingsModel(store: InMemoryHeroSettingsStore())
    private let heroBackground = HeroBackgroundSettingsModel(store: InMemoryHeroBackgroundSettingsStore())

    var body: some View {
        NavigationStack {
            PlozziOSHomeSettingsView(
                hero: hero, heroBackground: heroBackground,
                visibility: visibility, accounts: source.accounts
            )
        }
    }
}
#endif

private actor HomeSettingsLibraryProvider: MediaProvider {
    let session: UserSession
    let isOffline: Bool
    let kind: ProviderKind
    private(set) var libraryRequests = 0
    private var homeError: AppError?
    private let libraryTitle: String
    private var holdsLibraries: Bool
    private var libraryContinuation: CheckedContinuation<Void, Never>?
    private let homeLayout: ServerHomeLayout?
    private var holdsHome: Bool
    private var homeContinuations: [CheckedContinuation<Void, Never>] = []
    private let onFirstHomeRequest: (@Sendable () -> Void)?
    private var requestedHome = false

    init(
        name: String, isOffline: Bool = false, homeError: AppError? = nil,
        libraryTitle: String = "Movies", kind: ProviderKind = .jellyfin,
        holdsLibraries: Bool = false, homeLayout: ServerHomeLayout? = nil,
        holdsHome: Bool = false, onFirstHomeRequest: (@Sendable () -> Void)? = nil
    ) {
        self.isOffline = isOffline
        self.homeError = homeError
        self.libraryTitle = libraryTitle
        self.kind = kind
        self.holdsLibraries = holdsLibraries
        self.homeLayout = homeLayout
        self.holdsHome = holdsHome
        self.onFirstHomeRequest = onFirstHomeRequest
        session = UserSession(
            server: MediaServer(
                id: name, name: name,
                baseURL: URL(string: "https://home-settings.example.test")!, provider: kind
            ),
            userID: "viewer", userName: "Viewer", deviceID: "fixture", accessToken: "fixture"
        )
    }

    func setHomeError(_ error: AppError?) { homeError = error }
    func resumeLibraries() {
        holdsLibraries = false
        libraryContinuation?.resume()
        libraryContinuation = nil
    }
    func serverHomeLayout() async throws -> ServerHomeLayout? {
        if !requestedHome {
            requestedHome = true
            onFirstHomeRequest?()
        }
        if holdsHome { await withCheckedContinuation { homeContinuations.append($0) } }
        if let homeError { throw homeError }
        return homeLayout
    }

    func resumeHome() {
        holdsHome = false
        let pending = homeContinuations
        homeContinuations = []
        for continuation in pending { continuation.resume() }
    }

    func libraries() async throws -> [MediaLibrary] {
        libraryRequests += 1
        if holdsLibraries { await withCheckedContinuation { libraryContinuation = $0 } }
        if isOffline { throw AppError.serverUnreachable }
        return [MediaLibrary(id: "movies", title: libraryTitle, kind: .movie)]
    }
    func continueWatching(limit: Int) async throws -> [MediaItem] { [] }
    func latest(limit: Int) async throws -> [MediaItem] { [] }
    func items(in containerID: String, kind: MediaItemKind, page: PageRequest) async throws -> MediaPage {
        MediaPage(items: [], startIndex: page.startIndex, totalCount: 0)
    }
    func item(id: String) async throws -> MediaItem { throw AppError.notFound }
    func children(of itemID: String) async throws -> [MediaItem] { [] }
    func search(query: String, limit: Int) async throws -> [MediaItem] { [] }
    func playbackInfo(for itemID: String) async throws -> PlaybackRequest { throw AppError.notFound }
    func reportPlayback(_ progress: PlaybackProgress, event: PlaybackEvent) async throws {}
    nonisolated func imageURL(itemID: String, kind: ImageKind, maxWidth: Int?) -> URL? { nil }
}
