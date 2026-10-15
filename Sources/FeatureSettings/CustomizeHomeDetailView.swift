#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// Home layout, the shared individual-row arranger, and hero presentation.
/// Whole-library availability stays on the separate Libraries screen.
struct CustomizeHomeDetailView: View {
    let discoveredLibraries: LoadState<[AggregatedLibrary]>
    let homeVisibility: HomeLibraryVisibilityModel
    let accounts: [ResolvedAccount]
    @Environment(HeroSettingsModel.self) private var hero
    #if os(tvOS)
    @Environment(\.settingsInWorkspace) private var inWorkspace
    #endif

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
        #if os(tvOS)
        if inWorkspace {
            return layoutRows + homeRowsRows.map { $0.page() } + continueWatchingRows
                + (hero.settings.style == .carousel ? heroRows.map { $0.page() } : [])
        }
        #endif
        return layoutRows + homeRowsRows + continueWatchingRows
            + (hero.settings.style == .carousel ? heroRows : [])
    }

    private var layoutRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "home-layout",
                title: LocalizedStringResource(
                    "homeLayout.title",
                    defaultValue: "Home Layout",
                    comment: "Settings row that chooses how the Apple TV Home screen is laid out."
                ),
                subpage: SettingsDetailSubpage {
                    HeroSettingsDestination(libraries: homeVisibleLibraries, accounts: accounts)
                }
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
                if hero.allowsDiscovery {
                    Toggle("Show Discovery row", isOn: $hero.settings.showsDiscoverRow)
                        .toggleStyle(SettingsSwitchToggleStyle())
                    if hero.settings.showsDiscoverRow {
                        HeroSettingsLink(page: .discovery, libraries: homeVisibleLibraries, accounts: accounts)
                    }
                } else {
                    Text("Discovery is unavailable in Kids profiles. Library content follows the connected server user's restrictions.")
                        .settingsHelperText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: hero.settings.style)
    }

    private var homeRowsRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(id: "home-rows-all", title: "Rows on Home") {
                HomeRowsSettingsView(
                    libraries: homeVisibleLibraries, accounts: accounts, visibility: homeVisibility
                )
                .id(ObjectIdentifier(homeVisibility))
            }
        ]
    }

    private var homeVisibleLibraries: [AggregatedLibrary] {
        (discoveredLibraries.value ?? [])
            .filter { !$0.library.isMusic && homeVisibility.isVisibleOnHome($0.key) }
    }

    private var continueWatchingRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "continue-watching",
                title: "Continue Watching",
                description: "What the cards in this row show."
            ) {
                ContinueWatchingArtworkPicker(
                    style: Binding(
                        get: {
                            homeVisibility.continueWatchingShowsSeriesArtwork
                                ? .logoAndArtwork : .thumbnail
                        },
                        set: {
                            homeVisibility.setContinueWatchingShowsSeriesArtwork($0 == .logoAndArtwork)
                        }
                    )
                )
            }
        ]
    }

    private var heroRows: [SettingsSplitRow] {
        [
            SettingsSplitRow(
                id: "hero",
                title: "Hero",
                description: "Choose the content and details shown at the top of Home.",
                subpage: SettingsDetailSubpage {
                    HeroSettingsDestination(libraries: homeVisibleLibraries, accounts: accounts)
                }
            ) {
                VStack(alignment: .leading, spacing: SettingsRowMetrics.formSectionSpacing) {
                    HeroSettingsControls(libraries: homeVisibleLibraries, accounts: accounts)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        ]
    }
}
#endif
