import SwiftUI
import CoreModels
import CoreUI
import FeatureAuthCore

/// Keeps account linking inside the unresolved profile gate, not behind it in Settings.
public struct PlexAccountRecoveryView: View {
    private let name: String
    private let message: LocalizedStringResource
    private let signIn: PlexAuthViewModel?
    private let onSignIn: () -> Void
    private let onRetry: () -> Void
    private let onCancel: () -> Void
    private let onCancelSignIn: () -> Void

    public init(
        name: String,
        message: LocalizedStringResource,
        signIn: PlexAuthViewModel?,
        onSignIn: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCancelSignIn: @escaping () -> Void
    ) {
        self.name = name
        self.message = message
        self.signIn = signIn
        self.onSignIn = onSignIn
        self.onRetry = onRetry
        self.onCancel = onCancel
        self.onCancelSignIn = onCancelSignIn
    }

    public var body: some View {
        if let signIn {
            PlexAccountLinkView(viewModel: signIn, onCancel: onCancelSignIn)
        } else {
            PlexAccountRecoveryActions(
                name: name, message: message,
                onSignIn: onSignIn, onRetry: onRetry, onCancel: onCancel
            )
        }
    }
}

public struct PlexAccountLinkView: View {
    let viewModel: PlexAuthViewModel
    let onCancel: () -> Void

    public init(viewModel: PlexAuthViewModel, onCancel: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCancel = onCancel
    }

    public var body: some View {
        #if os(iOS)
        PlexMobileRecoveryLinkView(viewModel: viewModel, onCancel: onCancel)
        #else
        PlexLinkView(viewModel: viewModel, onCancel: onCancel)
        #endif
    }
}

private struct PlexAccountRecoveryActions: View {
    let name: String
    let message: LocalizedStringResource
    let onSignIn: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            #if os(iOS)
            ScrollView { actions }
            #else
            actions
                .onExitCommand(perform: onCancel)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("plex-account-recovery")
    }

    private var actions: some View {
        VStack(spacing: 24) {
            Text(verbatim: name).font(.headline)
            Text(message)
                .font(.title2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 800)
            Button("Sign In Again", action: onSignIn)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("plex-recovery-sign-in")
            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

#if os(iOS)
private struct PlexMobileRecoveryLinkView: View {
    let viewModel: PlexAuthViewModel
    let onCancel: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                switch viewModel.phase {
                case .idle, .requesting:
                    ProgressView("Requesting a Plex link code…")
                case let .awaitingLink(code, authorizationURL, _):
                    Section("Link your Plex account") {
                        Text(verbatim: code)
                            .font(.largeTitle.monospaced())
                            .frame(maxWidth: .infinity)
                            .textSelection(.enabled)
                        Button("Open Plex to link") { openURL(authorizationURL) }
                    }
                case .loadingServers, .selectingServer:
                    ProgressView("Loading your Plex servers…")
                case let .error(message):
                    Text(message)
                    Button("Try Again") { viewModel.retry() }
                }
            }
            .settingsPageSurface()
            .navigationTitle("Sign In Again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
            }
        }
        .onAppear { viewModel.startIfNeeded() }
        .onDisappear { viewModel.cancel() }
    }
}
#endif
