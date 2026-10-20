import CoreModels
import CoreUI
import SwiftUI
import UIKit

public struct PlaybackAdvancedSettingsView: View {
    @Bindable var model: PlaybackSettingsModel
    @State private var showsExternalPlayer = false

    public init(model: PlaybackSettingsModel) { self.model = model }

    public var body: some View {
        #if os(tvOS)
        SettingsSplitLayout(title: "Advanced", rows: ExternalPlayerSettingsRows.advanced(model: model))
        #else
        List {
            SettingsSectionGroup {
                Button { showsExternalPlayer = true } label: {
                    SettingsDisclosureLabel { Text("External player") }
                }
            }
        }
        .settingsPageSurface()
        .navigationTitle("Advanced")
        .navigationDestination(isPresented: $showsExternalPlayer) {
            ExternalPlayerSettingsView(model: model)
        }
        #endif
    }
}

struct ExternalPlayerSettingsRows {
    static func advanced(model: PlaybackSettingsModel) -> [SettingsSplitRow] {
        [
            .page(id: "external-player", title: "External player") {
                [
                    SettingsSplitRow(id: "default-player", title: "Default player") {
                        ExternalPlayerChoices(model: model)
                    },
                    SettingsSplitRow(id: "external-player-help", title: "About external playback") {
                        ExternalPlayerHelp()
                    },
                    SettingsSplitRow(id: "custom-player", title: "Custom player") {
                        CustomExternalPlayerControls(model: model)
                    }.page()
                ]
            }
        ]
    }
}

#if os(iOS)
private struct ExternalPlayerSettingsView: View {
    @Bindable var model: PlaybackSettingsModel
    @State private var showsCustomPlayer = false

    var body: some View {
        List {
            SettingsSectionGroup("Default player") {
                ExternalPlayerChoices(model: model)
            }
            SettingsSectionGroup {
                ExternalPlayerHelp()
            }
            SettingsSectionGroup {
                Button { showsCustomPlayer = true } label: {
                    SettingsDisclosureLabel { Text("Custom player") }
                }
            }
        }
        .settingsPageSurface()
        .navigationTitle("External player")
        .navigationDestination(isPresented: $showsCustomPlayer) {
            List {
                SettingsSectionGroup {
                    CustomExternalPlayerControls(model: model)
                }
            }
            .settingsPageSurface()
            .navigationTitle("Custom player")
        }
    }
}
#endif

private struct ExternalPlayerChoices: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: PlaybackSettingsModel
    @State private var installed: Set<ExternalPlayer> = [.builtIn]

    private var choices: [ExternalPlayer] {
        var result = ExternalPlayer.supported
        if !model.settings.externalPlayer.customURLTemplate.isEmpty { result.append(.custom) }
        if !result.contains(model.settings.externalPlayer.player) { result.append(model.settings.externalPlayer.player) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(tvOS)
            SettingsControlRows {
                ForEach(choices, id: \.self) { player in
                    SettingsCheckableRow(
                        title: title(player),
                        isChecked: model.settings.externalPlayer.player == player
                    ) {
                        model.settings.externalPlayer.player = player
                    }
                    .disabled(!isAvailable(player))
                    .accessibilityIdentifier("external-player-\(player.rawValue)")
                }
            }
            #else
            Picker("Default player", selection: $model.settings.externalPlayer.player) {
                ForEach(choices, id: \.self) { player in
                    title(player).tag(player).disabled(!isAvailable(player))
                }
            }
            .accessibilityIdentifier("external-player-selection")
            #endif
            if model.settings.externalPlayer.player == .vlc || model.settings.externalPlayer.player == .custom {
                Text("This player doesn't report progress to Plozz. Resume, watched status, and external-player features depend on the selected app.")
                    .settingsHelperText()
            }
        }
        .task { refreshInstalledPlayers() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshInstalledPlayers() }
        }
    }

    private func isAvailable(_ player: ExternalPlayer) -> Bool {
        player == .custom || installed.contains(player)
    }

    private func title(_ player: ExternalPlayer) -> Text {
        if player == .custom { return Text("Custom player") }
        if isAvailable(player) { return Text(verbatim: player.name) }
        return Text("\(player.name) (not installed)")
    }

    private func refreshInstalledPlayers() {
        installed = Set(ExternalPlayer.supported.filter {
            guard let scheme = $0.scheme, let url = URL(string: scheme + "://") else { return $0 == .builtIn }
            return UIApplication.shared.canOpenURL(url)
        })
    }
}

private struct ExternalPlayerHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choosing another player makes it the default for movies and episodes in this profile. Plozz opens the installed app when you press Play.")
            Text("Playable links, including server access tokens when required, are shared with the selected app. Only choose an app you trust.")
            Text("Infuse and Native Player can return progress when you close their player. Plozz's playback controls, skip markers, and autoplay aren't available in another app.")
            Text("Live TV stays in Plozz. For downloads, private network-share files, and videos requiring server conversion, Plozz offers its built-in player instead. Infuse requires version 8.4.7 or later for this integration.")
        }
        .settingsHelperText()
    }
}

private struct CustomExternalPlayerControls: View {
    @Bindable var model: PlaybackSettingsModel
    @State private var template = ""
    @State private var error: ExternalPlayerError?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("For an installed player with a documented URL scheme. Plozz replaces {url} with the encoded video link. Custom players don't receive resume positions or return progress.")
                .settingsHelperText()
            TextField("myplayer://play?url={url}", text: $template)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Player URL template")
                .accessibilityIdentifier("external-player-custom-template")
            Text("Don't include passwords or access tokens in this template.")
                .settingsHelperText()
            if let error { Text(error.message).foregroundStyle(.red) }
            if saved { Text("Custom player selected").settingsHelperText() }
            Button("Save and use custom player") {
                do {
                    try ExternalPlayerURL.validateCustomTemplate(template)
                    model.settings.externalPlayer = .init(player: .custom, customURLTemplate: template)
                    error = nil
                    saved = true
                } catch let failure as ExternalPlayerError {
                    error = failure
                } catch {
                    self.error = .invalidTemplate
                }
            }
            .accessibilityIdentifier("external-player-custom-save")
        }
        .onAppear { template = model.settings.externalPlayer.customURLTemplate }
        .onChange(of: template) { _, _ in saved = false }
    }
}
