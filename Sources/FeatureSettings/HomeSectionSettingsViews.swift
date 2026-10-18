#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

struct HomeEditorPage<Content: View>: View {
    let title: Text
    var showsHeader = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: pageSpacing) {
                #if os(tvOS)
                if showsHeader { SettingsPageHeader(title) }
                #endif
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .padding(.horizontal, SettingsFormMetrics.pageInset)
            .padding(.top, SettingsFormMetrics.pageTopInset)
            .padding(.bottom, SettingsFormMetrics.pageBottomInset)
            #else
            .padding()
            #endif
        }
        .navigationTitle(title)
        #if os(iOS)
        .settingsPageSurface()
        #endif
        #if os(tvOS)
        .scrollClipDisabled()
        .toggleStyle(SettingsSwitchToggleStyle())
        .toolbar(.hidden, for: .tabBar)
        #endif
    }

    private var pageSpacing: CGFloat {
        #if os(tvOS)
        SettingsFormMetrics.navigationRowSpacing
        #else
        12
        #endif
    }
}

struct HomeEditorLink<Destination: View, Label: View>: View {
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    #if !os(tvOS)
    @State private var isPresented = false
    #endif

    var body: some View {
        #if os(tvOS)
        SettingsPageLink(destination: destination) {
            label().padding(16).settingsGroupSurface(cornerRadius: SettingsRowMetrics.navigationCornerRadius)
        }
            .buttonStyle(SettingsFocusButtonStyle(size: .navigation))
        #else
        Button { isPresented = true } label: {
            label().padding(14)
                .settingsGroupSurface(cornerRadius: 12)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .navigationDestination(isPresented: $isPresented, destination: destination)
        #endif
    }
}

struct HomeEditorRowLabel: View {
    let title: Text
    let subtitle: Text?
    let symbol: String
    var accessory = "chevron.forward"

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                title.font(.body.weight(.medium))
                subtitle?.font(.footnote).settingsRowSecondary()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: accessory).font(.footnote).settingsRowSecondary().accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension HomeRowChoice {
    var homeEditorTitle: Text { localizedTitle.map(Text.init) ?? Text(verbatim: title) }
    var homeEditorSource: Text {
        if let library {
            return library.library.displayName + Text(verbatim: " · \(library.serverName)")
        }
        if let serverRow { return Text(verbatim: serverRow.serverName) }
        return id == .liveTV ? Text("All live sources") : Text("All libraries")
    }
}

struct HomeSectionChoiceLabel: View {
    let choice: HomeRowChoice
    var accessory = "chevron.forward"

    var body: some View {
        HomeEditorRowLabel(
            title: choice.homeEditorTitle, subtitle: choice.homeEditorSource,
            symbol: choice.id == .liveTV ? "tv" : "rectangle.grid.1x2", accessory: accessory
        )
    }
}

struct HomeSectionSettingsView: View {
    let choice: HomeRowChoice
    let inventory: HomeSectionCatalogModel
    let visibility: HomeLibraryVisibilityModel
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @SettingsPageDismiss private var dismiss
    @State private var failed = false
    @State private var reloadRevision = 0

    var body: some View {
        HomeEditorPage(title: choice.homeEditorTitle, showsHeader: true) {
            choice.homeEditorSource.font(.subheadline).plozzForeground(.secondary)
            if choice.id == .global(.continueWatching) {
                ContinueWatchingNextUpControl(visibility: visibility)
                ContinueWatchingArtworkPicker(
                    style: Binding(
                        get: { visibility.continueWatchingShowsSeriesArtwork ? .logoAndArtwork : .thumbnail },
                        set: { visibility.setContinueWatchingShowsSeriesArtwork($0 == .logoAndArtwork) }
                    )
                )
            }
            Button("Remove section", role: .destructive) {
                do {
                    try visibility.setHomeSectionVisible(false, id: choice.id, catalog: inventory.catalog)
                    dismiss()
                } catch { failed = true }
            }
            .plozzActionButton(role: .secondary)
            .disabled(inventory.isLoading)
            .accessibilityIdentifier("home-section-remove")
            if failed { InlineErrorMessage(Text("Couldn't update this section. Try again.")) }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
        }
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
    }
}

struct HomeAddSectionView: View {
    let inventory: HomeSectionCatalogModel
    let visibility: HomeLibraryVisibilityModel
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @SettingsPageDismiss private var dismiss
    @State private var failed = false
    @State private var reloadRevision = 0

    var body: some View {
        HomeEditorPage(title: Text("Add section"), showsHeader: true) {
            let catalog = inventory.catalog
            let disabled = Set(catalog.sections(in: visibility.visibility).disabled)
            let choices = catalog.editableChoices(in: visibility.visibility).filter { disabled.contains($0.id) }
            if choices.isEmpty && !inventory.isLoading {
                Text("All available sections are already on Home.").plozzForeground(.secondary)
            }
            ForEach(choices) { choice in
                Button {
                    do {
                        try visibility.setHomeSectionVisible(true, id: choice.id, catalog: inventory.catalog)
                        dismiss()
                    } catch { failed = true }
                } label: {
                    HomeSectionChoiceLabel(choice: choice, accessory: "plus")
                }
                .buttonStyle(SettingsFormButtonStyle())
                .disabled(inventory.isLoading)
                .accessibilityIdentifier("home-add-\(choice.id.presentationID)")
            }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
            if visibility.visibility.mergesNextUpRows {
                Text("Next Up is included in Continue Watching.").font(.footnote).plozzForeground(.secondary)
            }
            if failed { InlineErrorMessage(Text("Couldn't update this section. Try again.")) }
        }
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
    }
}

struct HomeHeroSettingsView: View {
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    let visibility: HomeLibraryVisibilityModel
    @Environment(HeroSettingsModel.self) private var hero
    #if os(tvOS)
    @State private var navigation = SettingsDetailNavigation()
    #endif

    private var availableLibraries: [AggregatedLibrary] {
        let accountIDs = Set(accounts.map(\.account.id))
        return libraries.filter {
            accountIDs.contains($0.accountID) && !$0.library.isMusic && visibility.isEnabled($0.key)
        }
    }

    var body: some View {
        #if os(tvOS)
        SettingsDetailPages(navigation: navigation) {
            page
        } detail: {
            HeroSettingsDestination(libraries: availableLibraries, accounts: accounts)
        }
        #else
        page
        #endif
    }

    @ViewBuilder private var page: some View {
        @Bindable var hero = hero
        HomeEditorPage(title: Text("Hero"), showsHeader: true) {
            #if os(tvOS)
            HomeLayoutPicker(layout: $hero.settings.style)
            if hero.settings.style == .followsFocus {
                Toggle("Show ratings", isOn: $hero.settings.showsRatings)
                if hero.settings.showsRatings {
                    Toggle("Show Common Sense age", isOn: $hero.settings.ratingPreferences.showsHeaderFamilyGuidance)
                    HeaderReviewScoreCountPicker(settings: $hero.settings.ratingPreferences)
                }
                if hero.allowsDiscovery {
                    Toggle("Show Discovery row", isOn: $hero.settings.showsDiscoverRow)
                    if hero.settings.showsDiscoverRow {
                        HeroSettingsLink(page: .discovery, libraries: availableLibraries, accounts: accounts)
                    }
                } else {
                    Text("Discovery is unavailable in Kids profiles.")
                        .settingsHelperText()
                }
            } else {
                HeroSettingsControls(libraries: availableLibraries, accounts: accounts)
            }
            #else
            HeroSettingsControls(libraries: availableLibraries, accounts: accounts)
            #endif
        }
    }
}

struct HomeCatalogStatus: View {
    let inventory: HomeSectionCatalogModel
    let accounts: [ResolvedAccount]
    let libraries: [AggregatedLibrary]
    let retry: () -> Void

    var body: some View {
        if inventory.isLoading { ProgressView("Loading available sections…") }
        ForEach(accounts.filter { inventory.serverFailures[$0.account.id] != nil }, id: \.account.id) { source in
            if let error = inventory.serverFailures[source.account.id], error != .cancelled {
                InlineErrorMessage(message(server: source.account.server.name, error: error))
                    .accessibilityIdentifier("home-server-failure-\(source.account.id)")
            }
        }
        ForEach(libraries.filter { inventory.libraryFailures[$0.key] != nil }) { library in
            InlineErrorMessage(Text("Couldn't load sections from \(library.library.title)."))
        }
        if !inventory.serverFailures.isEmpty || !inventory.libraryFailures.isEmpty {
            Button("Retry", action: retry)
                .plozzActionButton(role: .secondary)
        }
    }

    private func message(server: String, error: AppError) -> Text {
        if error == .serverUnreachable { return Text("\(server) is offline.") }
        if error.requiresSignIn { return Text("Sign in to \(server) again.") }
        return Text("Couldn't load sections from \(server).")
    }
}

struct HomeRowPresetsView: View {
    let inventory: HomeSectionCatalogModel
    let visibility: HomeLibraryVisibilityModel
    let libraries: [AggregatedLibrary]
    let accounts: [ResolvedAccount]
    @State private var resetDefaults: HomeRowCustomization.Defaults?
    @State private var reloadRevision = 0

    var body: some View {
        HomeEditorPage(title: Text("Starting layout"), showsHeader: true) {
            Text("Choose a starting point, then customize individual sections.")
                .font(.footnote).plozzForeground(.secondary)
            ForEach([HomeRowCustomization.Defaults.matchServer, .combined], id: \.self) { preset in
                Button {
                    guard visibility.visibility.rowCustomization?.defaults != preset else { return }
                    resetDefaults = preset
                } label: {
                    HStack {
                        Text(title(preset))
                        Spacer()
                        if visibility.visibility.rowCustomization?.defaults == preset {
                            Image(systemName: "checkmark").accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(SettingsFormButtonStyle())
                .accessibilityAddTraits(visibility.visibility.rowCustomization?.defaults == preset ? .isSelected : [])
                .accessibilityIdentifier("home-row-preset-\(preset.rawValue)")
                .confirmationDialog(
                    "Replace your row arrangement?",
                    isPresented: Binding(
                        get: { resetDefaults == preset },
                        set: { if !$0 { resetDefaults = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button(title(preset)) {
                        visibility.useRowDefaults(preset)
                        resetDefaults = nil
                    }
                    Button("Cancel", role: .cancel) { resetDefaults = nil }
                } message: {
                    if preset == .matchServer { Text("Follow your servers' Home sections.") }
                    else { Text("Start with rows across all libraries.") }
                }
            }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
        }
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
    }

    private func title(_ preset: HomeRowCustomization.Defaults) -> LocalizedStringResource {
        preset == .matchServer ? "Match server" : "Combined rows"
    }
}
#endif
