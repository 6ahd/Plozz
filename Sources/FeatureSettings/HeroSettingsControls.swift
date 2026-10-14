#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

enum HeroSettingsPage: String, CaseIterable {
    case content, appearance, rotation, trailers, discovery, libraries, collections

    var title: LocalizedStringResource {
        switch self {
        case .content: "Content"
        case .appearance: "Appearance"
        case .rotation: "Rotation"
        case .trailers: "Trailers"
        case .discovery: "Discovery"
        case .libraries: "Random libraries"
        case .collections: "Collections"
        }
    }

    var initialRowID: String {
        switch self {
        case .content: "hero-hide-watched"
        case .appearance: "hero-ratings"
        case .rotation: "hero-item-count"
        case .trailers: "hero-trailers"
        case .discovery: "hero-provider-labels"
        case .libraries: "hero-all-libraries"
        case .collections: "hero-collection-done"
        }
    }
}

/// Shared controls keep TV and mobile terminology, grouping and Kids policy aligned.
public struct HeroSettingsControls: View {
    private let libraries: [AggregatedLibrary]
    private let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero

    public init(libraries: [AggregatedLibrary], accounts: [ResolvedAccount]) {
        self.libraries = libraries
        self.accounts = accounts
    }

    public var body: some View {
        @Bindable var hero = hero
        Toggle("Show hero", isOn: $hero.settings.isEnabled)
            .toggleStyle(SettingsSwitchToggleStyle())
        if hero.settings.isEnabled {
            ForEach([HeroSettingsPage.content, .appearance, .rotation, .trailers], id: \.self) { page in
                HeroSettingsLink(page: page, libraries: libraries, accounts: accounts)
            }
        }
    }
}

struct HeroSettingsLink: View {
    let page: HeroSettingsPage
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]

    var body: some View {
        SettingsDetailLink(pageID: page.rawValue) {
            HeroSettingsScreen(page: page, libraries: libraries, accounts: accounts)
        } label: {
            HStack {
                Text(page.title)
                Spacer(minLength: 16)
                #if os(tvOS)
                Image(systemName: "chevron.forward")
                #endif
            }
        }
        .accessibilityIdentifier("hero-settings-\(page.rawValue)")
        .modifier(ViewCustomizationRowFocus(id: "hero-settings-\(page.rawValue)"))
    }
}

struct HeroSettingsDestination: View {
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(SettingsDetailNavigation.self) private var navigation

    var body: some View {
        if let page = navigation.pageID.flatMap(HeroSettingsPage.init(rawValue:)) {
            HeroSettingsScreen(page: page, libraries: libraries, accounts: accounts)
        }
    }
}

struct HeroSettingsScreen: View {
    let page: HeroSettingsPage
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(HeroBackgroundSettingsModel.self) private var background
    @Environment(SettingsDetailNavigation.self) private var parentNavigation: SettingsDetailNavigation?
    @State var childNavigation = SettingsDetailNavigation()

    var body: some View {
        @Bindable var hero = hero
        if page == .collections {
            HeroCollectionPickerView(selections: $hero.settings.collections, libraries: libraries, accounts: accounts)
        } else {
            #if os(tvOS)
            SettingsDetailPages(navigation: childNavigation) {
                ViewCustomizationList(title: page.title, initialRowID: initialRowID) {
                    form
                        .environment(childNavigation)
                        .toggleStyle(SettingsSwitchToggleStyle())
                }
                .environment(parentNavigation)
            } detail: {
                HeroSettingsDestination(libraries: libraries, accounts: accounts)
            }
            #else
            ViewCustomizationList(title: page.title, initialRowID: initialRowID) {
                form
            }
            #endif
        }
    }

    private var initialRowID: String {
        if page == .discovery && !hero.allowsDiscovery { return "view-customization-back" }
        if page == .libraries && eligibleLibraries.isEmpty { return "view-customization-back" }
        return page.initialRowID
    }

    @ViewBuilder private var form: some View {
        switch page {
        case .content: content
        case .appearance: appearance
        case .rotation: rotation
        case .trailers: trailers
        case .discovery: discovery
        case .libraries: randomLibraries
        case .collections: EmptyView()
        }
    }

    private var content: some View {
        @Bindable var hero = hero
        return Group {
            HeroSettingsGroup {
                Toggle("Hide watched titles", isOn: $hero.settings.hideWatched)
                    .modifier(ViewCustomizationRowFocus(id: "hero-hide-watched"))
            }
            HeroSettingsGroup(title: "Content sources") {
                ForEach(HeroSourceKind.allCases.filter { $0 != .featured }, id: \.self) { source in
                    Toggle(source.displayName, isOn: sourceBinding(source))
                }
                if hero.allowsDiscovery {
                    Toggle(HeroSourceKind.featured.displayName, isOn: sourceBinding(.featured))
                }
            }
            if !hero.allowsDiscovery {
                kidsExplanation
            }
            if hero.settings.sources.contains(where: {
                $0 == .randomFromLibrary || $0 == .collection || $0 == .watchlist
                    || ($0 == .featured && hero.allowsDiscovery)
            }) {
                HeroSettingsGroup(title: "Source options") {
                    if hero.allowsDiscovery, hero.settings.isEnabled(.featured) {
                        link(.discovery)
                    }
                    if hero.settings.isEnabled(.randomFromLibrary) { link(.libraries) }
                    if hero.settings.isEnabled(.collection) { link(.collections) }
                    if hero.settings.isEnabled(.watchlist) {
                        Toggle("Prefer less recently shown Watchlist titles", isOn: $hero.settings.watchlistDiscoveryEnabled)
                    }
                }
            }
        }
    }

    private var appearance: some View {
        @Bindable var hero = hero
        return HeroSettingsGroup(title: "Ratings") {
            Toggle("Show ratings", isOn: $hero.settings.showsRatings)
                .modifier(ViewCustomizationRowFocus(id: "hero-ratings"))
            if hero.settings.showsRatings {
                Toggle("Show Common Sense age", isOn: $hero.settings.ratingPreferences.showsHeaderFamilyGuidance)
                HeaderReviewScoreCountPicker(settings: $hero.settings.ratingPreferences)
            }
        }
    }

    private var rotation: some View {
        @Bindable var hero = hero
        return HeroSettingsGroup {
            #if os(tvOS)
            LabeledSettingRow("Items in rotation") {
                SettingsStepper(options: Array(HeroSettings.maxItemsRange), selection: $hero.settings.maxItems, title: { "\($0)" })
            }
            .modifier(ViewCustomizationRowFocus(id: "hero-item-count"))
            #else
            Stepper("Items: \(hero.settings.maxItems)", value: $hero.settings.maxItems, in: HeroSettings.maxItemsRange)
            #endif
            Toggle("Rotate automatically", isOn: $hero.settings.autoAdvance)
            if hero.settings.autoAdvance {
                #if os(tvOS)
                LabeledSettingRow("Seconds per title") {
                    SettingsStepper(
                        options: Array(HeroSettings.autoAdvanceRange), selection: $hero.settings.autoAdvanceSeconds,
                        verbatimTitle: { Duration.seconds($0).formatted(.units(allowed: [.seconds], width: .narrow)) }
                    )
                }
                #else
                Stepper("Every \(hero.settings.autoAdvanceSeconds) seconds",
                        value: $hero.settings.autoAdvanceSeconds, in: HeroSettings.autoAdvanceRange)
                #endif
            }
        }
    }

    private var trailers: some View {
        @Bindable var background = background
        return HeroSettingsGroup {
            Toggle("Play trailer behind the hero", isOn: $background.settings.homeTrailerEnabled)
                .modifier(ViewCustomizationRowFocus(id: "hero-trailers"))
            if background.settings.homeTrailerEnabled {
                Toggle("Start muted", isOn: $background.settings.homeTrailerMuted)
            }
        }
    }

    @ViewBuilder private var discovery: some View {
        @Bindable var hero = hero
        if hero.allowsDiscovery {
            HeroSettingsGroup(
                title: "Provider labels",
                detail: "Show provider names on Discovery titles. This does not change which titles appear."
            ) {
                Toggle("Show provider labels", isOn: $hero.settings.showsDiscoverySources)
                    .modifier(ViewCustomizationRowFocus(id: "hero-provider-labels"))
            }
            HeroSettingsGroup(
                title: "Discovery providers",
                detail: "Recommendations may include titles outside your libraries. Seerr is only needed to request them."
            ) {
                ForEach(HeroDiscoverySource.allCases) { source in
                    Toggle(isOn: discoveryBinding(source)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: source.displayName)
                            Text(source.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if hero.settings.discoverySources.isEmpty {
                    Text("Select a provider to see Discovery recommendations.")
                }
            }
        } else {
            kidsExplanation
        }
    }

    private var kidsExplanation: some View {
        Text("Discovery is unavailable in Kids profiles. Library content follows the connected server user's restrictions.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var eligibleLibraries: [AggregatedLibrary] {
        libraries.filter { $0.library.kind == .movie || $0.library.kind == .series }
    }

    private var randomLibraries: some View {
        @Bindable var hero = hero
        return HeroSettingsGroup(
            detail: "Choose at least one library. All libraries includes new libraries added to Home."
        ) {
            if eligibleLibraries.isEmpty {
                Text("No movie or TV libraries are enabled on Home.")
            } else {
                Toggle("All libraries on Home", isOn: Binding(
                    get: { hero.settings.randomLibraryKeys.isEmpty },
                    set: { all in hero.settings.randomLibraryKeys = all ? [] : Set(eligibleLibraries.map(\.key)) }
                ))
                .modifier(ViewCustomizationRowFocus(id: "hero-all-libraries"))
                if !hero.settings.randomLibraryKeys.isEmpty {
                    ForEach(eligibleLibraries) { library in
                        Toggle(isOn: Binding(
                            get: { hero.settings.randomLibraryKeys.contains(library.key) },
                            set: { selected in
                                if selected { hero.settings.randomLibraryKeys.insert(library.key) }
                                else { hero.settings.randomLibraryKeys.remove(library.key) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                library.library.displayName
                                Text(verbatim: library.serverName).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(hero.settings.randomLibraryKeys == [library.key])
                    }
                }
            }
        }
    }

    private func link(_ page: HeroSettingsPage) -> some View {
        HeroSettingsLink(page: page, libraries: libraries, accounts: accounts)
    }

    private func sourceBinding(_ source: HeroSourceKind) -> Binding<Bool> {
        Binding(
            get: { hero.settings.sources.contains(source) },
            set: { selected in
                guard source != .featured || hero.allowsDiscovery else { return }
                var sources = Set(hero.settings.sources)
                if selected { sources.insert(source) } else { sources.remove(source) }
                hero.settings.sources = HeroSourceKind.allCases.filter(sources.contains)
            }
        )
    }

    private func discoveryBinding(_ source: HeroDiscoverySource) -> Binding<Bool> {
        Binding(
            get: { hero.settings.discoverySources.contains(source) },
            set: { selected in
                guard hero.allowsDiscovery else { return }
                var sources = Set(hero.settings.discoverySources)
                if selected { sources.insert(source) } else { sources.remove(source) }
                hero.settings.discoverySources = HeroDiscoverySource.allCases.filter(sources.contains)
            }
        )
    }
}

private struct HeroSettingsGroup<Content: View>: View {
    var title: LocalizedStringResource? = nil
    var detail: LocalizedStringResource? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 24) {
            if let title { Text(title).settingsSectionHeader() }
            content()
            if let detail { Text(detail).settingsHelperText().fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.bottom, 20)
        #else
        Section {
            content()
        } header: {
            if let title { Text(title) }
        } footer: {
            if let detail { Text(detail) }
        }
        #endif
    }
}
#endif
