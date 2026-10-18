#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI

/// The shared section editor adapts existing row feeds without changing their identities.
public struct HomeRowsSettingsView: View {
    public let libraries: [AggregatedLibrary]
    public let accounts: [ResolvedAccount]
    public let visibility: HomeLibraryVisibilityModel
    @Environment(HeroSettingsModel.self) private var hero
    @Environment(HeroBackgroundSettingsModel.self) private var heroBackground
    @State private var inventory: HomeSectionCatalogModel
    @State private var isReordering = false
    @State private var isLifting = false
    @State private var reloadRevision = 0
    @State private var editError: AppError?

    public init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel
    ) {
        self.init(libraries: libraries, accounts: accounts, visibility: visibility, inventory: HomeSectionCatalogModel())
    }

    init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel, inventory: HomeSectionCatalogModel
    ) {
        self.libraries = libraries
        self.accounts = accounts
        self.visibility = visibility
        _inventory = State(initialValue: inventory)
    }

    private var requestID: HomeSectionCatalogModel.RequestID {
        HomeSectionCatalogModel.requestID(libraries: libraries, accounts: accounts, visibility: visibility)
    }

    public var body: some View {
        HomeEditorPage(title: Text("Customize Home")) {
            #if os(tvOS)
            HStack {
                SettingsPageHeader("Customize Home")
                reorderButton
            }
            .focusSection()
            #endif
            HomeEditorLink {
                HomeHeroSettingsView(libraries: libraries, accounts: accounts, visibility: visibility)
                    .environment(hero)
                    .environment(heroBackground)
            } label: {
                HomeEditorRowLabel(
                    title: Text("Hero"), subtitle: heroSummary,
                    symbol: "rectangle.topthird.inset.filled", accessory: "chevron.forward"
                )
            }
            .accessibilityIdentifier("home-section-hero")
            .disabled(isReordering)

            let catalog = inventory.requestID == requestID ? inventory.catalog : HomeSectionCatalog(libraries: [])
            let sections = catalog.sections(in: visibility.visibility)
            let choices = catalog.editableChoices(in: visibility.visibility)
            if isReordering {
                let byID = Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                LiftableReorderList(
                    sections: .init(enabled: sections.enabled, disabled: []),
                    disabledSectionTitle: "Hidden", disabledPlaceholder: "No hidden rows",
                    isLifting: $isLifting, allowsHiding: false,
                    row: { id in
                        let choice = byID[id]
                        return .init(
                            title: choice?.homeEditorTitle ?? Text("Section"),
                            symbolName: "rectangle.grid.1x2",
                            providerKind: choice?.library?.providerKind ?? choice?.serverRow?.providerKind,
                            mediaShareTransport: choice?.library?.transportKind,
                            subtitle: choice?.homeEditorSource
                        )
                    },
                    onChange: { order in
                        do {
                            try visibility.reorderHomeSections(order.enabled, catalog: catalog)
                            editError = nil
                        } catch { editError = (error as? AppError) ?? .invalidResponse }
                    }
                )
                .disabled(inventory.isLoading)
                .accessibilityIdentifier("home-section-reorder-list")
            } else {
                ForEach(sections.enabled, id: \.self) { id in
                    if let choice = choices.first(where: { $0.id == id }) {
                        HomeEditorLink {
                            HomeSectionSettingsView(
                                choice: choice, inventory: inventory, visibility: visibility,
                                libraries: libraries, accounts: accounts
                            )
                        } label: {
                            HomeSectionChoiceLabel(choice: choice)
                        }
                        .accessibilityIdentifier("home-section-\(id.presentationID)")
                    }
                }
                HomeEditorLink {
                    HomeAddSectionView(
                        inventory: inventory, visibility: visibility, libraries: libraries, accounts: accounts
                    )
                } label: {
                    Label("Add section", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("home-section-add")

                HomeEditorLink {
                    HomeRowPresetsView(
                        inventory: inventory, visibility: visibility, libraries: libraries, accounts: accounts
                    )
                } label: {
                    HomeEditorRowLabel(
                        title: Text("Starting layout"), subtitle: presetTitle,
                        symbol: "rectangle.3.group", accessory: "chevron.forward"
                    )
                }
                .accessibilityIdentifier("home-section-presets")
            }
            if editError != nil {
                InlineErrorMessage(Text("Couldn't update this section. Try again."))
            }
            HomeCatalogStatus(inventory: inventory, accounts: accounts, libraries: libraries) {
                reloadRevision += 1
            }
            .disabled(isReordering)
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { reorderButton }
        }
        #endif
        .task(id: HomeSectionCatalogModel.loadID(
            libraries: libraries, accounts: accounts, visibility: visibility, revision: reloadRevision
        )) {
            await inventory.load(libraries: libraries, accounts: accounts, visibility: visibility)
        }
        .onChange(of: requestID) { _, _ in
            isReordering = false
            isLifting = false
            editError = nil
        }
    }

    private var reorderButton: some View {
        Button {
            isReordering.toggle()
            isLifting = false
        } label: {
            if isReordering { Text("Done") }
            else { Text("Reorder") }
        }
        .disabled(isLifting || (!isReordering && (inventory.isLoading
            || inventory.catalog.sections(in: visibility.visibility).enabled.count < 2)))
        .accessibilityIdentifier("home-section-reorder")
    }

    private var presetTitle: Text {
        switch visibility.visibility.rowCustomization?.defaults {
        case .matchServer: Text("Match server")
        case .combined: Text("Combined rows")
        default: Text("Custom arrangement")
        }
    }

    private var heroSummary: Text {
        #if os(tvOS)
        if hero.settings.style == .followsFocus { return Text("Showcase") }
        #endif
        return hero.settings.isEnabled ? Text("Pinned at top") : Text("Off")
    }
}
#endif
