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
    @State private var serverRows: [HomeServerRowDefinition] = []
    @State private var failures: [String: AppError] = [:]
    @State private var isLoading = false
    @State private var isLifting = false
    @State private var reloadRevision = 0
    @State private var catalogIdentity: RequestID?

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
        let native = (visibility.visibility.rowCustomization?.availableServerRows ?? []) + serverRows
        var seen = Set<HomeRowID>()
        let nativeChoices = native.filter { row in
            guard case .server = row.id, seen.insert(row.id).inserted else { return false }
            return row.section.libraryID.map { id in
                visibility.isEnabled("\(row.accountID):\(id)")
            } != false
        }.map(HomeRowChoice.init(serverRow:))
        return shared.filter { $0.id != .libraries && $0.id != .liveTV }
            + nativeChoices
            + availableLibraries.flatMap { library in
                HomeRowChoice.baseRows(for: library)
                    + (recommendations[library.key] ?? []).map {
                        HomeRowChoice(section: $0, library: library)
                    }
            } + shared.filter { $0.id == .libraries || $0.id == .liveTV }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HomeRowPresetActions(
                selection: visibility.visibility.rowCustomization?.defaults,
                resolved: visibility.visibility.rowCustomization?.resolvedDefaults,
                matchFailed: visibility.serverMatchError != nil,
                onSelect: { preset in
                    visibility.useRowDefaults(preset)
                    Task { await visibility.prepareServerDefaults(accounts: accounts) }
                }
            )
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
                        providerKind: choice?.library?.providerKind ?? choice?.serverRow?.providerKind,
                        mediaShareTransport: choice?.library?.transportKind,
                        subtitle: choice?.library.map {
                            $0.library.displayName + Text(verbatim: " · \($0.serverName)")
                        } ?? choice?.serverRow.map {
                            Text(verbatim: $0.serverName)
                        } ?? (id == .liveTV ? Text("All live sources") : Text("All libraries"))
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
            credentials: accounts.map(\.credentialRevision),
            users: accounts.map(\.provider.session.userID), plexHomeUsers: accounts.map(\.plexHomeUserID),
            libraries: availableLibraries.map(\.key),
            scope: ObjectIdentifier(visibility), revision: reloadRevision
        )) {
            let identity = RequestID(
                accounts: accounts.map(\.account.id),
                credentials: accounts.map(\.credentialRevision),
                users: accounts.map(\.provider.session.userID), plexHomeUsers: accounts.map(\.plexHomeUserID),
                libraries: availableLibraries.map(\.key),
                scope: ObjectIdentifier(visibility), revision: 0
            )
            if catalogIdentity != identity {
                recommendations = [:]
                serverRows = []
                catalogIdentity = identity
            }
            await visibility.prepareServerDefaults(accounts: accounts)
            async let recommendations: Void = loadRecommendations()
            async let sections: Void = loadServerRows()
            _ = await (recommendations, sections)
        }
    }

    private struct RequestID: Hashable {
        let accounts: [String]
        let credentials: [CredentialRevision]
        let users: [String]
        let plexHomeUsers: [String?]
        let libraries: [String]
        let scope: ObjectIdentifier
        let revision: Int
    }

    private func loadServerRows() async {
        if visibility.visibility.rowCustomization?.defaults == .matchServer,
           visibility.visibility.rowCustomization?.resolvedDefaults != nil {
            serverRows = visibility.visibility.rowCustomization?.availableServerRows ?? []
            return
        }
        await withTaskGroup(of: (String, Result<[HomeServerRowDefinition], AppError>).self) { group in
            var next = 0
            func enqueue() {
                guard next < accounts.count, !Task.isCancelled else { return }
                let source = accounts[next]
                next += 1
                group.addTask {
                    do {
                        let layout = try await source.provider.serverHomeLayout()
                        let rows = (layout?.sections ?? []).map {
                            HomeServerRowDefinition(
                                accountID: source.account.id, serverName: source.account.server.name,
                                providerKind: source.account.server.provider, section: $0
                            )
                        }
                        return (source.account.id, .success(rows))
                    } catch is CancellationError {
                        return (source.account.id, .failure(.cancelled))
                    } catch {
                        return (source.account.id, .failure((error as? AppError) ?? .unknown("")))
                    }
                }
            }
            for _ in 0..<min(3, accounts.count) { enqueue() }
            var loaded = Dictionary(grouping: serverRows, by: \.accountID)
            while let (accountID, result) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                switch result {
                case let .success(rows): loaded[accountID] = rows
                case let .failure(error):
                    if error != .cancelled {
                        PlozzLog.app.error("Home server row catalog request failed; preserving known rows")
                    }
                }
                enqueue()
            }
            serverRows = accounts.flatMap { loaded[$0.account.id] ?? [] }
        }
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
    let selection: HomeRowCustomization.Defaults?
    let resolved: HomeResolvedRowDefaults?
    let matchFailed: Bool
    let onSelect: (HomeRowCustomization.Defaults) -> Void
    @State private var resetDefaults: HomeRowCustomization.Defaults?

    private func actionTitle(for preset: HomeRowCustomization.Defaults) -> LocalizedStringResource {
        preset == .matchServer ? "Match server" : "Combined rows"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets").settingsSectionHeader()
            Text("Use your server's Home arrangement, or combine your libraries. You can reorder or hide any row.")
                .settingsSectionDescription()
                .fixedSize(horizontal: false, vertical: true)
            if selection != .matchServer && selection != .combined {
                Text("Custom arrangement")
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("home-row-preset-custom")
            }
            ViewPreferenceChoiceGroup {
                ForEach([HomeRowCustomization.Defaults.matchServer, .combined], id: \.self) { preset in
                    Button {
                        guard selection != preset else { return }
                        resetDefaults = preset
                    } label: {
                        HStack {
                            Text(actionTitle(for: preset))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selection == preset {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsFormButtonStyle())
                    .accessibilityAddTraits(selection == preset ? .isSelected : [])
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
                        if preset == .matchServer {
                            Text("Follow your servers' Home arrangements. With multiple servers, common rows are combined and the other server rows stay visible. This adapts until you customize a row.")
                        } else {
                            Text("Start with rows across all libraries. You can also add individual library or server rows, then arrange everything together.")
                        }
                    }
                }
            }
            if selection == .matchServer {
                matchDescription
                    .font(.footnote)
                    .plozzForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var matchDescription: Text {
        if matchFailed {
            return resolved != nil
                ? Text("Some server arrangements are unavailable. Keeping known rows and showing defaults where needed.")
                : Text("The server arrangement isn't available yet. Default rows are shown for now.")
        }
        switch resolved?.mode {
        case .combined:
            return Text("Common rows are combined across servers. Each server's other default rows stay visible.")
        case .providerFallback:
            return Text("This source doesn't share a saved Home arrangement. Using its default rows.")
        case .server where resolved?.source == .promotedHubs:
            return Text("Using Plex's promoted Home rows. Other clients' pinned-library choices aren't shared.")
        case .server:
            return Text("Following your server's Home rows. Music and reading are not included.")
        case nil:
            return Text("Follow your servers' Home rows, combining common rows when you have multiple servers.")
        }
    }
}
#endif
