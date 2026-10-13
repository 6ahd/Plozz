#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// Home layout, the shared individual-row arranger, and hero presentation.
/// Whole-library availability stays on the separate Libraries screen.
struct CustomizeHomeDetailView: View {
    /// Discovered libraries (with kind + owning account) — powers the per-library
    /// row checklists and the hero's Random-source picker.
    let discoveredLibraries: LoadState<[AggregatedLibrary]>
    /// The per-profile Home/visibility model (merge switch, global-row + per-library
    /// row selection, library visibility).
    let homeVisibility: HomeLibraryVisibilityModel
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(HeroBackgroundSettingsModel.self) private var heroBackground

    /// Keep existing callers compatible without retaining a Seerr dependency.
    init(
        discoveredLibraries: LoadState<[AggregatedLibrary]>,
        homeVisibility: HomeLibraryVisibilityModel,
        seerConfigured _: Bool,
        accounts: [ResolvedAccount] = []
    ) {
        self.discoveredLibraries = discoveredLibraries
        self.homeVisibility = homeVisibility
        self.accounts = accounts
    }

    var body: some View {
        SettingsSplitLayout(title: "Customize Home", rows: rows)
    }

    private var rows: [SettingsSplitRow] {
        layoutRows + homeRowsRows + continueWatchingRows
            + (hero.settings.style == .carousel ? heroRows : [])
    }

    // MARK: - Layout

    /// How Home is arranged, first because it decides what the rest applies to:
    /// the Hero pane belongs to Fullscreen Hero alone, and Showcase's few options sit
    /// under the picker here.
    private var layoutRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "home-layout",
                title: LocalizedStringResource(
                    "homeLayout.title",
                    defaultValue: "Home Layout",
                    comment: "Settings row that chooses how the Apple TV Home screen is laid out."
                )
            ) {
                layoutForm
            }
        ]
    }

    @ViewBuilder private var layoutForm: some View {
        @Bindable var hero = hero
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            HomeLayoutPicker(layout: $hero.settings.style)

            if hero.settings.style == .followsFocus {
                Toggle("Show ratings", isOn: $hero.settings.showsRatings)
                    .toggleStyle(SettingsSwitchToggleStyle())
                if hero.settings.showsRatings {
                    Toggle("Show Common Sense age", isOn: $hero.settings.ratingPreferences.showsHeaderFamilyGuidance)
                    HeaderReviewScoreCountPicker(settings: $hero.settings.ratingPreferences)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $hero.settings.showsDiscoverRow) {
                        Text(LocalizedStringResource(
                            "homeLayout.showDiscoverRow",
                            defaultValue: "Show a Discover row",
                            comment: "Switch in the Showcase Home layout: add a row of recommended titles named Discover."
                        ))
                    }
                        .toggleStyle(SettingsSwitchToggleStyle())
                    Text(LocalizedStringResource(
                        "homeLayout.showDiscoverRow.detail",
                        defaultValue: "Picks from outside your libraries, after Continue Watching.",
                        comment: "Describes the Discover row: recommended titles not in the user's libraries, placed after the Continue Watching row."
                    ))
                        .settingsHelperText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hero.settings.showsDiscoverRow {
                    FeaturedDiscoverySettings(sources: $hero.settings.discoverySources)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: hero.settings.style)
    }

    // MARK: - Rows on Home
    private var homeRowsRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "home-rows-all",
                title: "Rows on Home",
            ) {
                homeRowsDetail
            }
        ]
    }

    @ViewBuilder private var homeRowsDetail: some View {
        HomeRowsSettingsView(
            libraries: homeVisibleLibraries, accounts: accounts, visibility: homeVisibility
        )
        .id(ObjectIdentifier(homeVisibility))
    }

    /// Preserve discovery order so the arranger matches Home before any edits.
    private var homeVisibleLibraries: [AggregatedLibrary] {
        (discoveredLibraries.value ?? [])
            .filter { !$0.library.isMusic && homeVisibility.isVisibleOnHome($0.key) }
    }

    // MARK: - Continue Watching (its own entry — a row's LOOK, not its presence)

    /// Continue Watching's card style gets its own pane rather than riding in the
    /// "Rows on Home" checklist, which answers a different question — which rows
    /// appear — and whose every control is a checkmark against a row name.
    private var continueWatchingRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "continue-watching",
                title: "Continue Watching",
                description: "What the cards in this row show.",
            ) {
                ContinueWatchingArtworkPicker(
                    style: Binding(
                        get: {
                            homeVisibility.continueWatchingShowsSeriesArtwork
                                ? .logoAndArtwork
                                : .thumbnail
                        },
                        set: {
                            homeVisibility.setContinueWatchingShowsSeriesArtwork($0 == .logoAndArtwork)
                        }
                    )
                )
            }
        ]
    }

    // MARK: - Hero (a single feature row: the whole hero form in one pane)

    /// One master row — "Hero" — whose detail pane holds the entire hero form:
    /// the on/off switch, then (revealed when on) Sources, Items, Random
    /// Libraries and Auto-Advance as headed groups. Previously these were five
    /// separate (mostly indented) master rows, which buried the feature; now Hero
    /// reads as one dedicated space.
    private var heroRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "hero",
                title: "Hero",
                description: "A cinematic, rotating spotlight at the top of Home, with a Continue Watching row tucked under its lower edge.",
            ) {
                heroForm
            }
        ]
    }

    @ViewBuilder private var heroForm: some View {
        @Bindable var hero = hero
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            Toggle("Show the hero on Home", isOn: $hero.settings.isEnabled)
                .toggleStyle(SettingsSwitchToggleStyle())

            if hero.settings.isEnabled {
                Toggle("Show ratings", isOn: $hero.settings.showsRatings)
                    .toggleStyle(SettingsSwitchToggleStyle())
                if hero.settings.showsRatings {
                    Toggle("Show Common Sense age", isOn: $hero.settings.ratingPreferences.showsHeaderFamilyGuidance)
                    HeaderReviewScoreCountPicker(settings: $hero.settings.ratingPreferences)
                }
                spotlightForm
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: hero.settings.isEnabled)
    }

    /// Where the Fullscreen Hero's picks come from and how it rotates.
    @ViewBuilder private var spotlightForm: some View {
        @Bindable var hero = hero
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show discovery sources", isOn: $hero.settings.showsDiscoverySources)
                    .toggleStyle(SettingsSwitchToggleStyle())
                Text("Show the catalogs behind each title.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(
                "Hide watched movies, shows, and episodes",
                isOn: $hero.settings.hideWatched
            )
            .toggleStyle(SettingsSwitchToggleStyle())

            SettingsDetailGroup(title: "Sources") {
                SettingsCheckList(
                    options: orderedHeroSources,
                    title: { Text($0.displayName) },
                    isChecked: { hero.settings.sources.contains($0) },
                    onToggle: { toggleSource($0) }
                )
            }

            if hero.settings.isEnabled(.featured) {
                FeaturedDiscoverySettings(sources: $hero.settings.discoverySources)
            }

            if hero.settings.isEnabled(.randomFromLibrary) {
                SettingsDetailGroup(
                    title: "Random Libraries",
                    description: "Leave all selected to use every library on Home."
                ) {
                    randomLibrariesContent
                }
            }

            if hero.settings.isEnabled(.watchlist) {
                SettingsDetailGroup(
                    title: "Watchlist picks",
                    description: "Prefer titles you haven't seen in the hero recently. Turn off to keep your watchlist order."
                ) {
                    Toggle(
                        "Discovery rotation",
                        isOn: $hero.settings.watchlistDiscoveryEnabled
                    )
                    .toggleStyle(SettingsSwitchToggleStyle())
                }
            }

            SettingsDetailGroup(title: "Rotation") {
                VStack(alignment: .leading, spacing: 24) {
                    LabeledSettingRow("Items in rotation") {
                        SettingsStepper(
                            options: Array(HeroSettings.maxItemsRange),
                            selection: $hero.settings.maxItems,
                            title: { "\($0)" }
                        )
                    }
                    Toggle("Rotate automatically", isOn: $hero.settings.autoAdvance)
                        .toggleStyle(SettingsSwitchToggleStyle())
                    if hero.settings.autoAdvance {
                        LabeledSettingRow("Seconds per title") {
                            SettingsStepper(
                                options: Array(HeroSettings.autoAdvanceRange),
                                selection: $hero.settings.autoAdvanceSeconds,
                                verbatimTitle: { Duration.seconds($0).formatted(.units(allowed: [.seconds], width: .narrow)) }
                            )
                        }
                    }
                }
            }

            heroTrailerGroup
        }
    }

    @ViewBuilder private var heroTrailerGroup: some View {
        @Bindable var heroBackground = heroBackground
        SettingsDetailGroup(title: "Trailer") {
            VStack(alignment: .leading, spacing: 24) {
                Toggle(
                    "Play the trailer behind the hero",
                    isOn: $heroBackground.settings.homeTrailerEnabled
                )
                .toggleStyle(SettingsSwitchToggleStyle())
                if heroBackground.settings.homeTrailerEnabled {
                    Toggle(
                        "Start muted",
                        isOn: $heroBackground.settings.homeTrailerMuted
                    )
                    .toggleStyle(SettingsSwitchToggleStyle())
                }
            }
        }
    }

    // MARK: - Hero helpers (unchanged from the old Home Display page)

    private var randomEligibleLibraries: [AggregatedLibrary] {
        (discoveredLibraries.value ?? [])
            .filter { $0.library.kind == .movie || $0.library.kind == .series }
            .filter { homeVisibility.isVisibleOnHome($0.key) }
            .sorted { lhs, rhs in
                if lhs.serverName != rhs.serverName { return lhs.serverName < rhs.serverName }
                return lhs.library.title.localizedCaseInsensitiveCompare(rhs.library.title) == .orderedAscending
            }
    }

    @ViewBuilder private var randomLibrariesContent: some View {
        let libraries = randomEligibleLibraries
        if libraries.isEmpty {
            Text("No movie or TV libraries are shown on this profile's Home yet.")
                .font(.callout)
                .plozzForeground(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SettingsCheckList(
                options: libraries,
                title: { $0.library.displayName },
                subtitle: { Text(verbatim: $0.serverName) },
                isChecked: { isRandomLibraryOn($0.key, universe: libraries) },
                onToggle: { toggleRandomLibrary($0.key, universe: libraries) }
            )
        }
    }

    /// Library sources first, then Featured. Stored source order still follows
    /// `allCases`, preserving the existing curation/interleaving order.
    private var orderedHeroSources: [HeroSourceKind] {
        HeroSourceKind.allCases.filter { $0 != .featured } + [.featured]
    }

    private func toggleSource(_ source: HeroSourceKind) {
        var next = Set(hero.settings.sources)
        if next.contains(source) { next.remove(source) } else { next.insert(source) }
        hero.settings.sources = HeroSourceKind.allCases.filter { next.contains($0) }
    }

    /// A library feeds the Random source when it's explicitly selected, or when
    /// nothing is (empty == "all libraries").
    private func isRandomLibraryOn(_ key: String, universe: [AggregatedLibrary]) -> Bool {
        let keys = hero.settings.randomLibraryKeys
        return keys.isEmpty || keys.contains(key)
    }

    private func toggleRandomLibrary(_ key: String, universe: [AggregatedLibrary]) {
        let allKeys = Set(universe.map(\.key))
        var keys = hero.settings.randomLibraryKeys.isEmpty ? allKeys : hero.settings.randomLibraryKeys
        if keys.contains(key) { keys.remove(key) } else { keys.insert(key) }
        keys.formIntersection(allKeys)
        // Canonicalise "everything selected" back to empty.
        hero.settings.randomLibraryKeys = (keys == allKeys) ? [] : keys
    }
}

private struct FeaturedDiscoverySettings: View {
    @Binding var sources: [HeroDiscoverySource]

    var body: some View {
        SettingsDetailGroup(
            title: "Featured discovery",
            description: "Choose the catalogs used for Featured. Titles may not be in your libraries. Seerr is only needed to request titles."
        ) {
            SettingsCheckList(
                options: HeroDiscoverySource.allCases,
                title: { Text(verbatim: $0.displayName) },
                subtitle: { Text($0.detail) },
                isChecked: { sources.contains($0) },
                onToggle: toggleSource
            )
            if sources.isEmpty {
                Text("No sources selected. Featured won't add discovery titles.")
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleSource(_ source: HeroDiscoverySource) {
        var selected = Set(sources)
        if selected.contains(source) {
            selected.remove(source)
        } else {
            selected.insert(source)
        }
        sources = HeroDiscoverySource.allCases.filter(selected.contains)
    }
}

#endif
