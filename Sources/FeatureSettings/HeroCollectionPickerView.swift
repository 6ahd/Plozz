#if canImport(SwiftUI)
import CoreModels
import SwiftUI

public struct HeroCollectionPickerView: View {
    @Binding private var selection: HeroCollectionSelection?
    private let libraries: [AggregatedLibrary]
    private let accounts: [ResolvedAccount]
    @State private var libraryKey: String?
    @FocusState private var hasFocus: Bool
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

    private var eligibleLibraries: [AggregatedLibrary] {
        libraries.filter { library in
            guard library.library.kind == .movie || library.library.kind == .series,
                  let account = accounts.first(where: { $0.account.id == library.accountID }) else { return false }
            return (account.provider as? any CapabilityReporting)?
                .capabilities.contains(.libraryCollections) == true
        }
    }

    public var body: some View {
        let eligible = eligibleLibraries
        let preferredKey = libraryKey ?? selection?.libraryKey
        let key = eligible.first(where: { $0.key == preferredKey })?.key ?? eligible.first?.key
        List {
            if let selection {
                Section("Selected collection") {
                    Text(verbatim: selection.title)
                    Button("Clear selection") { self.selection = nil }
                        .focused($hasFocus)
                }
            }
            if eligible.isEmpty {
                Text("No enabled movie or TV libraries support collections.")
            } else {
                Section("Library") {
                    Picker("Library", selection: Binding(
                        get: { key ?? "" },
                        set: { libraryKey = $0 }
                    )) {
                        ForEach(eligible) { library in
                            Text(verbatim: "\(library.serverName) / \(library.accountName) \u{2014} \(library.library.title)")
                                .tag(library.key)
                        }
                    }
                    .focused($hasFocus)
                }
                if let library = eligible.first(where: { $0.key == key }),
                   let account = accounts.first(where: { $0.account.id == library.accountID }) {
                    HeroCollectionListView(
                        selection: $selection, library: library, provider: account.provider,
                        serverUserID: account.plexHomeUserID ?? account.provider.session.userID
                    )
                    .id([
                        library.key, account.credentialRevision.rawValue.uuidString,
                        account.provider.session.userID, account.plexHomeUserID ?? ""
                    ])
                } else {
                    Text("Choose an available library to select a collection.")
                }
            }
        }
        .navigationTitle("Choose a collection")
        .onChange(of: hasFocus) { _, focused in
            if focused { detailNavigation?.focusArrived() }
        }
    }
}

private struct HeroCollectionListView: View {
    @Binding var selection: HeroCollectionSelection?
    let library: AggregatedLibrary
    let serverUserID: String
    @State private var model: HeroCollectionListModel
    @State private var request = 0
    @FocusState private var focusedCollection: String?
    @Environment(SettingsDetailNavigation.self) private var detailNavigation: SettingsDetailNavigation?

    init(
        selection: Binding<HeroCollectionSelection?>,
        library: AggregatedLibrary,
        provider: any MediaProvider,
        serverUserID: String
    ) {
        _selection = selection
        self.library = library
        self.serverUserID = serverUserID
        _model = State(initialValue: HeroCollectionListModel(provider: provider, libraryID: library.library.id))
    }

    var body: some View {
        Section("Collections") {
            ForEach(model.items) { collection in
                collectionButton(collection)
            }
            if model.isLoading {
                ProgressView()
            } else if let error = model.error {
                Text(error.userMessage)
                Button("Retry") { request += 1 }
            } else if model.hasMore {
                Button("Load more") { request += 1 }
            } else if model.items.isEmpty {
                Text("No collections in this library.")
            }
        }
        .onChange(of: focusedCollection) { _, value in
            if value != nil { detailNavigation?.focusArrived() }
        }
        .task(id: request) { await model.loadNextPage() }
    }

    private func collectionButton(_ collection: MediaItem) -> some View {
        let selected = selection?.accountID == library.accountID
            && selection?.libraryID == library.library.id
            && selection?.serverUserID == serverUserID
            && selection?.collectionID == collection.id
        return Button {
            selection = HeroCollectionSelection(
                accountID: library.accountID, libraryID: library.library.id,
                collectionID: collection.id, title: collection.title, serverUserID: serverUserID
            )
        } label: {
            HStack {
                Text(verbatim: collection.title)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
        }
        .focused($focusedCollection, equals: collection.id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
