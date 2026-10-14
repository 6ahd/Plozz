#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

public struct HeroCollectionPickerView: View {
    @Binding private var selection: HeroCollectionSelection?
    private let libraries: [AggregatedLibrary]
    private let accounts: [ResolvedAccount]
    @State private var sourceID: HeroCollectionPickerSource.ID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsDetailNavigation.self) private var detailNavigation: SettingsDetailNavigation?

    public init(
        selection: Binding<HeroCollectionSelection?>,
        libraries: [AggregatedLibrary],
        accounts: [ResolvedAccount]
    ) {
        _selection = selection
        self.libraries = libraries
        self.accounts = accounts
    }

    public var body: some View {
        let sources = HeroCollectionPickerSource.available(libraries: libraries, accounts: accounts)
        let preferred = sourceID ?? selection.map {
            HeroCollectionPickerSource.ID(accountID: $0.accountID, libraryID: $0.libraryID)
        }
        let source = sources.first(where: { $0.id == preferred }) ?? sources.first
        ViewCustomizationList(
            title: "Choose a collection", initialRowID: source?.id.focusID ?? "hero-collection-done"
        ) {
            if let selection {
                HeroCollectionSection(title: "Selected collection") {
                    Text(verbatim: selection.title)
                    Button("Clear selection") { self.selection = nil }
                        .modifier(ViewCustomizationRowFocus(id: "hero-collection-clear"))
                }
            }
            if let source {
                HeroCollectionSources(
                    sources: sources,
                    selection: Binding(get: { source.id }, set: { sourceID = $0 })
                )
                if let account = accounts.first(where: { $0.account.id == source.id.accountID }) {
                    HeroCollectionListView(
                        selection: $selection, source: source.id, provider: account.provider,
                        serverUserID: account.plexHomeUserID ?? account.provider.session.userID
                    )
                    .id([
                        source.id.focusID, account.credentialRevision.rawValue.uuidString,
                        account.provider.session.userID, account.plexHomeUserID ?? ""
                    ])
                }
            } else {
                Text("No available collection sources.")
                Button("Done") {
                    if let detailNavigation {
                        detailNavigation.pop(animated: !reduceMotion)
                    } else {
                        dismiss()
                    }
                }
                .modifier(ViewCustomizationRowFocus(id: "hero-collection-done"))
            }
        }
    }
}

private struct HeroCollectionSources: View {
    let sources: [HeroCollectionPickerSource]
    @Binding var selection: HeroCollectionPickerSource.ID

    var body: some View {
        HeroCollectionSection(title: "Source") {
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sources) { source in
                    SettingsCheckableRow(
                        title: source.libraryTitle.map { Text(verbatim: $0) } ?? Text("Personal collections"),
                        subtitle: Text(verbatim: "\(source.serverName) / \(source.accountName)"),
                        titleLineLimit: nil, subtitleLineLimit: nil,
                        isChecked: source.id == selection,
                        flushLeading: false,
                        action: { selection = source.id }
                    )
                    .accessibilityIdentifier(source.id.focusID)
                    .modifier(ViewCustomizationRowFocus(id: source.id.focusID))
                }
            }
            #else
            Picker("Source", selection: $selection) {
                ForEach(sources) { source in
                    VStack(alignment: .leading) {
                        if let title = source.libraryTitle {
                            Text(verbatim: title)
                        } else {
                            Text("Personal collections")
                        }
                        Text(verbatim: "\(source.serverName) / \(source.accountName)")
                            .font(.caption)
                    }
                    .tag(source.id)
                }
            }
            #endif
        }
    }
}

private struct HeroCollectionListView: View {
    @Binding var selection: HeroCollectionSelection?
    let source: HeroCollectionPickerSource.ID
    let serverUserID: String
    @State private var model: HeroCollectionListModel
    @State private var request = 0

    init(
        selection: Binding<HeroCollectionSelection?>,
        source: HeroCollectionPickerSource.ID,
        provider: any MediaProvider,
        serverUserID: String
    ) {
        _selection = selection
        self.source = source
        self.serverUserID = serverUserID
        _model = State(initialValue: HeroCollectionListModel(provider: provider, libraryID: source.libraryID))
    }

    var body: some View {
        HeroCollectionSection(title: "Collections") {
            ForEach(model.items) { collection in
                HeroCollectionChoice(
                    selection: $selection, accountID: source.accountID, libraryID: source.libraryID,
                    serverUserID: serverUserID, collectionID: collection.id, title: collection.title
                )
            }
            if model.isLoading {
                ProgressView()
            } else if let error = model.error {
                Text(error.userMessage)
                Button("Retry") { request += 1 }
                    .modifier(ViewCustomizationRowFocus(id: "hero-collection-retry"))
            } else if model.hasMore {
                Button("Load more") { request += 1 }
                    .modifier(ViewCustomizationRowFocus(id: "hero-collection-more"))
            } else if model.items.isEmpty {
                Text("No collections in this source.")
            }
        }
        .task(id: request) { await model.loadNextPage() }
    }
}

private struct HeroCollectionChoice: View {
    @Binding var selection: HeroCollectionSelection?
    let accountID: String
    let libraryID: String?
    let serverUserID: String
    let collectionID: String
    let title: String // l10n:content — collection name from the server

    var body: some View {
        let choice = HeroCollectionSelection(
            accountID: accountID, libraryID: libraryID,
            collectionID: collectionID, title: title, serverUserID: serverUserID
        )
        let selected = selection?.accountID == accountID && selection?.libraryID == libraryID
            && selection?.serverUserID == serverUserID && selection?.collectionID == collectionID
        Button { selection = choice } label: {
            HStack {
                Text(verbatim: title)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            #endif
        }
        #if os(tvOS)
        .buttonStyle(SettingsFocusButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityIdentifier("hero-collection-choice-\(collectionID)")
        .modifier(ViewCustomizationRowFocus(id: "hero-collection-choice-\(collectionID)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HeroCollectionSection<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
        #else
        Section {
            content()
        } header: {
            Text(title)
        }
        #endif
    }
}
#endif
