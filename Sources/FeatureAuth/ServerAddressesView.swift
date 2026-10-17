#if canImport(SwiftUI)
import SwiftUI
import CoreModels
import CoreUI
import FeatureAuthCore

public struct ServerAddressesView: View {
    @State private var model: ServerAddressesModel
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    public init(
        account: Account, store: any AccountPersisting,
        isAuthorized: @escaping @MainActor () -> Bool,
        onChanged: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: ServerAddressesModel(
            account: account, store: store, isAuthorized: isAuthorized, onChanged: onChanged
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let server = model.pairingServer {
                SiloSignInView(
                    server: server, deviceID: model.account.deviceID, verificationOnly: true,
                    onAuthenticated: { session in
                        operation = Task { await model.completePairing(session) }
                    },
                    onCancel: model.cancelPairing
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top) {
                            SettingsPageHeader("Connection addresses")
                            Spacer()
                            Button("Close", systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly)
                        }
                        #if os(tvOS)
                        .focusSection()
                        #endif
                        Text(verbatim: model.account.server.name)
                            .font(.headline)
                        Text("Plozz prefers a reachable local address and tries another saved address if the connection fails. These addresses apply to this sign-in on this device.")
                            .plozzForeground(.secondary)
                        ServerSavedAddresses(model: model)
                        ServerAddAddressForm(model: model) {
                            operation = Task { await model.add() }
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: PlozzTheme.Metrics.settingsContentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollClipDisabled()
            }
        }
        .onDisappear {
            operation?.cancel()
            model.cancel()
        }
    }
}

private struct ServerSavedAddresses: View {
    let model: ServerAddressesModel
    @State private var pendingRemoval: URL?

    var body: some View {
        SettingsSectionGroup("Saved addresses") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign-in address").font(.caption)
                Text(verbatim: model.account.server.baseURL.absoluteString)
                    .lineLimit(2)
            }
            ForEach(model.alternatives, id: \.self) { url in
                HStack {
                    Text(verbatim: url.absoluteString)
                        .lineLimit(2)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle", role: .destructive) {
                        pendingRemoval = url
                    }
                    .disabled(model.isWorking)
                }
                .accessibilityElement(children: .contain)
            }
        } footer: {
            if model.account.server.provider == .plex {
                Text("Plex also discovers its own local, remote, and relay addresses automatically.")
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
        .confirmationDialog("Remove this address?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval { model.remove(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }
}

private struct ServerAddAddressForm: View {
    @Bindable var model: ServerAddressesModel
    let add: () -> Void

    var body: some View {
        SettingsSectionGroup("Add an address") {
            TextField("Server address", text: $model.address)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .disabled(model.isWorking)
            Button("Verify and add address", systemImage: "plus", action: add)
                .buttonStyle(SettingsFormButtonStyle())
                .disabled(model.isWorking || model.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityElement(children: .contain)
            if model.isWorking { ProgressView("Verifying address…") }
            if let error = model.errorMessage {
                Text(error)
                    .accessibilityIdentifier("serverAddressError")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Only add addresses you trust for this server. Your sign-in will be used at each saved address. HTTP connections are not encrypted.")
                if model.account.server.provider == .silo {
                    Text("Approve the new address in Silo, then choose the same account and profile. Your saved sign-in stays unchanged.")
                }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}
#endif
