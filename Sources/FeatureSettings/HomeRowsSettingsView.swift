#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreNetworking
import CoreUI

/// Shared arranger; only the input catalog is fetched, only while this page is open.
public struct HomeRowsSettingsView: View {
    public let libraries: [AggregatedLibrary]
    public let accounts: [ResolvedAccount]
    public let visibility: HomeLibraryVisibilityModel
    @State private var recommendations: [String: [LibrarySection]] = [:]
    @State private var failures: [String: AppError] = [:]
    @State private var isLoading = false
    @State private var isLifting = false
    @State private var reloadRevision = 0

    public init(
        libraries: [AggregatedLibrary], accounts: [ResolvedAccount],
        visibility: HomeLibraryVisibilityModel
    ) {
        self.libraries = libraries
        self.accounts = accounts
        self.visibility = visibility
    }

    private var availableLibraries: [AggregatedLibrary] {
        libraries.filter { !$0.library.isMusic && visibility.isEnabled($0.key) }
    }

    private var choices: [HomeRowChoice] {
        let shared = HomeRowChoice.shared
        return shared.filter { $0.id != .libraries }
            + availableLibraries.flatMap { library in
                HomeRowChoice.baseRows(for: library)
                    + (recommendations[library.key] ?? []).map {
                        HomeRowChoice(section: $0, library: library)
                    }
            } + shared.filter { $0.id == .libraries }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeRowPresetActions(onSelect: { visibility.useRowDefaults($0) })
            .disabled(isLifting)
            VStack(alignment: .leading, spacing: 8) {
                Text("Rows").settingsSectionHeader()
                Text("Arrange rows from any library together. Move a row below Hidden to turn it off.")
                    .font(.footnote)
                    .plozzForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let choices = choices
            let byID = Dictionary(choices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            LiftableReorderList(
                sections: visibility.visibility.rowSections(choices: choices),
                disabledSectionTitle: "Hidden",
                disabledPlaceholder: "No hidden rows",
                isLifting: $isLifting,
                row: { id in
                    let choice = byID[id]
                    return LiftableReorderList<HomeRowID>.Row(
                        title: choice?.localizedTitle.map(Text.init)
                            ?? Text(verbatim: choice?.title ?? ""),
                        symbolName: choice?.library == nil ? "square.stack.3d.up.fill" : "rectangle.grid.1x2",
                        providerKind: choice?.library?.providerKind,
                        mediaShareTransport: choice?.library?.transportKind,
                        subtitle: choice?.library.map {
                            $0.library.displayName + Text(verbatim: " · \($0.serverName)")
                        } ?? Text("Shared rows")
                    )
                },
                onChange: { visibility.applyRows($0, choices: choices) }
            )
            if isLoading {
                ProgressView("Loading available rows…")
            }
            ForEach(availableLibraries.filter { failures[$0.key] != nil }) { library in
                VStack(alignment: .leading, spacing: 8) {
                    InlineErrorMessage(
                        Text("Couldn't load recommended rows from \(library.library.title). Your saved choices are unchanged.")
                    )
                    .font(.footnote)
                    Button("Retry") { reloadRevision += 1 }
                        .plozzActionButton(role: .secondary)
                        .disabled(isLifting)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: RequestID(
            accounts: accounts.map(\.account.id),
            credentials: accounts.map(\.account.credentialRevision),
            users: accounts.map(\.provider.session.userID),
            libraries: availableLibraries.map(\.key),
            scope: ObjectIdentifier(visibility), revision: reloadRevision
        )) {
            recommendations = [:]
            await loadRecommendations()
        }
    }

    private struct RequestID: Hashable {
        let accounts: [String]
        let credentials: [CredentialRevision]
        let users: [String]
        let libraries: [String]
        let scope: ObjectIdentifier
        let revision: Int
    }

    private func loadRecommendations() async {
        isLoading = true
        defer { isLoading = false }
        failures = [:]
        let sources = availableLibraries.compactMap { library -> (AggregatedLibrary, any MediaProvider)? in
            guard LibraryHomeRowKind.available(for: library).contains(.hubs),
                  let provider = accounts.first(where: { $0.account.id == library.accountID })?.provider
            else { return nil }
            return (library, provider)
        }
        await withTaskGroup(of: (String, Result<[LibrarySection], AppError>).self) { group in
            var next = 0
            func enqueue() {
                guard next < sources.count, !Task.isCancelled else { return }
                let (library, provider) = sources[next]
                next += 1
                group.addTask {
                    do {
                        return (library.key, .success(try await provider.homeHubs(
                            libraryID: library.library.id, kind: library.library.kind,
                            limit: 8, includeUnpromoted: true
                        )))
                    } catch is CancellationError {
                        return (library.key, .failure(.cancelled))
                    } catch {
                        return (library.key, .failure((error as? AppError) ?? .unknown("")))
                    }
                }
            }
            for _ in 0..<min(3, sources.count) { enqueue() }
            while let (key, result) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch result {
                case let .success(rows): recommendations[key] = rows
                case let .failure(error):
                    failures[key] = error
                    if error != .cancelled {
                        PlozzLog.app.error("Home row catalog request failed")
                    }
                }
                enqueue()
            }
        }
    }
}

private struct HomeRowPresetActions: View {
    let onSelect: (HomeRowCustomization.Defaults) -> Void
    @State private var resetDefaults: HomeRowCustomization.Defaults?

    private func actionTitle(for preset: HomeRowCustomization.Defaults) -> LocalizedStringResource {
        preset == .provider ? "Use server-style rows" : "Use shared rows"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").settingsSectionHeader()
            Text("You can mix shared rows and individual library rows in any order.")
                .settingsSectionDescription()
                .fixedSize(horizontal: false, vertical: true)
            ViewPreferenceChoiceGroup {
                ForEach([HomeRowCustomization.Defaults.provider, .combined], id: \.self) { preset in
                    Button {
                        resetDefaults = preset
                    } label: {
                        Label {
                            Text(actionTitle(for: preset))
                                .multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                                .accessibilityHidden(true)
                        }
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsFormButtonStyle())
                    .accessibilityIdentifier("home-row-preset-\(preset.rawValue)")
                    .confirmationDialog(
                        "Replace your row arrangement?",
                        isPresented: Binding(
                            get: { resetDefaults == preset },
                            set: { if !$0, resetDefaults == preset { resetDefaults = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button(actionTitle(for: preset)) {
                            onSelect(preset)
                            resetDefaults = nil
                        }
                        Button("Cancel", role: .cancel) { resetDefaults = nil }
                    } message: {
                        if preset == .provider {
                            Text("Start with rows suited to your servers, alongside shared Continue Watching and Watchlist rows. You can then reorder, hide, or add any row.")
                        } else {
                            Text("Start with shared rows that combine your libraries. You can then add individual library rows and arrange everything together.")
                        }
                    }
                }
            }
        }
    }
}
#endif
