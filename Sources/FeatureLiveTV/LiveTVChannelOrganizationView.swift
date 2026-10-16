import CoreModels
import CoreUI
import FeatureLiveTVCore
import SwiftUI

struct LiveTVChannelOrganizationView: View {
    let model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    var canMutate: () -> Bool = { true }

    var body: some View {
        LiveTVSettingsPage(title: "Manage IPTV channels") {
            LiveTVOrganizationFailure(model: model)
            SettingsSectionGroup {
                NavigationLink {
                    LiveTVCategoryManagementView(model: model, imports: imports, canMutate: canMutate)
                } label: {
                    Label("Categories", systemImage: "rectangle.stack")
                }
                NavigationLink {
                    LiveTVRegionManagementView(model: model, canMutate: canMutate)
                } label: {
                    Label("Countries and languages", systemImage: "globe")
                }
                NavigationLink {
                    LiveTVHiddenChannelManagementView(model: model, canMutate: canMutate)
                } label: {
                    HStack {
                        Label("Hidden channels", systemImage: "eye.slash")
                        Spacer()
                        Text(model.hiddenChannelEntries.count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("live-tv-manage-hidden")
            } footer: {
                Text("Category choices apply to new channels after a playlist refresh. Hidden channels are kept, not deleted. These choices belong to this profile.")
            }
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .disabled(!canMutate())
    }
}

private struct LiveTVCategoryManagementView: View {
    let model: LiveTVPrototypeModel
    let imports: LiveTVPrototypeImportModel
    let canMutate: () -> Bool
    @State private var query = ""

    var body: some View {
        LiveTVSettingsPage(title: "IPTV categories") {
            LiveTVOrganizationFailure(model: model)
            SettingsSectionGroup {
                TextField("Find a category", text: $query)
                    .autocorrectionDisabled()
                Text("Show overrides regional filtering. Hide keeps the category out of the guide. Automatic follows your country and language choices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 16) {
                ForEach(model.categorySummaries.filter {
                    query.isEmpty || $0.rule.name.localizedStandardContains(query)
                }) { summary in
                    LiveTVCategoryManagementRow(
                        model: model, summary: summary,
                        sourceName: imports.configuration.playlists.first { $0.id == summary.rule.sourceID }?.name
                            ?? imports.configuration.servers.first { $0.id == summary.rule.sourceID }?.name,
                        canMutate: canMutate
                    )
                }
            }
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .disabled(!canMutate())
    }
}

private struct LiveTVCategoryManagementRow: View {
    let model: LiveTVPrototypeModel
    let summary: LiveTVCategorySummary
    let sourceName: String?
    let canMutate: () -> Bool

    var body: some View {
        SettingsSectionGroup {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.rule.name)
                if let sourceName { Text(sourceName).font(.caption).foregroundStyle(.secondary) }
                Text("\(summary.visibleCount) of \(summary.channelCount) channels visible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            PrototypeSelectionLink(
                title: "Visibility",
                selection: Binding(
                    get: { model.organization.categories[summary.id]?.visibility ?? .automatic },
                    set: { visibility in
                        guard canMutate() else { return }
                        var rule = model.organization.categories[summary.id] ?? summary.rule
                        rule.visibility = visibility
                        _ = model.setCategoryRule(rule)
                    }
                ), options: LiveTVCategoryRule.Visibility.allCases
            ) { value in
                switch value {
                case .automatic: Text("Automatic")
                case .shown: Text("Show")
                case .hidden: Text("Hide")
                }
            }
            Toggle("Favorite category", isOn: Binding(
                get: { model.organization.categories[summary.id]?.isFavorite == true },
                set: { favorite in
                    guard canMutate() else { return }
                    var rule = model.organization.categories[summary.id] ?? summary.rule
                    rule.isFavorite = favorite
                    _ = model.setCategoryRule(rule)
                }
            ))
            .accessibilityLabel("Favorite \(summary.rule.name)")
        }
        #if os(tvOS)
        .toggleStyle(SettingsSwitchToggleStyle(flushLeading: false))
        #endif
    }
}

private struct LiveTVRegionManagementView: View {
    let model: LiveTVPrototypeModel
    let canMutate: () -> Bool

    var body: some View {
        LiveTVSettingsPage(title: "Countries and languages") {
            LiveTVOrganizationFailure(model: model)
            SettingsSectionGroup {
                Toggle("Filter IPTV by country or language", isOn: Binding(
                    get: { model.organization.region.isEnabled },
                    set: { enabled in
                        guard canMutate() else { return }
                        var filter = model.organization.region
                        filter.isEnabled = enabled
                        _ = model.setRegionalFilter(filter)
                    }
                ))
                NavigationLink {
                    LiveTVRegionChoices(model: model, country: true, canMutate: canMutate)
                } label: { Label("Countries", systemImage: "globe") }
                NavigationLink {
                    LiveTVRegionChoices(model: model, country: false, canMutate: canMutate)
                } label: { Label("Languages", systemImage: "character.bubble") }
            } footer: {
                Text("A channel stays visible if its country OR language matches. Tags come from the playlist; Plozz doesn't guess from channel names. Untagged and nonmatching channels move to Hidden channels, where you can show them again.")
            }
            SettingsSectionGroup {
                Text("Showing a category or individual channel overrides regional filtering. Hiding a category still hides its channels unless you show a channel individually.")
                    .font(.footnote)
            }
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .disabled(!canMutate())
        #if os(tvOS)
        .toggleStyle(SettingsSwitchToggleStyle(flushLeading: false))
        #endif
    }
}

private struct LiveTVRegionChoices: View {
    let model: LiveTVPrototypeModel
    let country: Bool
    let canMutate: () -> Bool
    @Environment(\.locale) private var locale
    @State private var query = ""

    private var options: [String] { country ? model.organizationCountries : model.organizationLanguages }

    var body: some View {
        LiveTVSettingsPage(title: country ? "Countries" : "Languages") {
            LiveTVOrganizationFailure(model: model)
            SettingsSectionGroup {
                TextField("Search", text: $query).autocorrectionDisabled()
                if options.isEmpty {
                    Text("Your playlist hasn't supplied these tags. You can still show or hide named categories.")
                }
            }
            LazyVStack(spacing: 12) {
                ForEach(options.filter { query.isEmpty || name($0).localizedStandardContains(query) }, id: \.self) { value in
                    Toggle(name(value), isOn: Binding(
                        get: {
                            let filter = model.organization.region
                            return (country ? filter.countries : filter.languages).contains(value)
                        },
                        set: { selected in
                            guard canMutate() else { return }
                            var filter = model.organization.region
                            if country {
                                if selected { filter.countries.insert(value) } else { filter.countries.remove(value) }
                            } else {
                                if selected { filter.languages.insert(value) } else { filter.languages.remove(value) }
                            }
                            _ = model.setRegionalFilter(filter)
                        }
                    ))
                }
            }
        }
        .disabled(!canMutate())
        #if os(tvOS)
        .toggleStyle(SettingsSwitchToggleStyle(flushLeading: false))
        #endif
    }

    private func name(_ value: String) -> String {
        (country ? locale.localizedString(forRegionCode: value.uppercased())
            : locale.localizedString(forLanguageCode: value)) ?? value
    }
}

struct LiveTVHiddenChannelManagementView: View {
    let model: LiveTVPrototypeModel
    var canMutate: () -> Bool = { true }
    @State private var query = ""

    var body: some View {
        LiveTVSettingsPage(title: "Hidden channels") {
            LiveTVOrganizationFailure(model: model)
            SettingsSectionGroup {
                TextField("Find a hidden channel", text: $query).autocorrectionDisabled()
                Button("Reset category and region visibility") {
                    guard canMutate() else { return }
                    _ = model.resetOrganizationVisibility()
                }
                Text("Reset keeps individually hidden channels and scan exclusions. Show channel makes an individual exception to category and regional filtering.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.hiddenChannelEntries.isEmpty {
                ContentUnavailableView("No hidden channels", systemImage: "eye")
            }
            LazyVStack(spacing: 12) {
                ForEach(model.hiddenChannelEntries.filter {
                    query.isEmpty || $0.name.localizedStandardContains(query)
                }) { channel in
                    SettingsSectionGroup {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.name)
                                Text(channel.reason.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if channel.reason != .scan {
                                Button("Show channel") {
                                    guard canMutate() else { return }
                                    _ = model.showChannel(channel.id)
                                }
                                .accessibilityLabel("Show \(channel.name)")
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(SettingsFocusButtonStyle(size: .contained))
        .disabled(!canMutate())
    }
}

private extension LiveTVChannelHiddenReason {
    var explanation: LocalizedStringResource {
        switch self {
        case .channel: "Hidden individually"
        case .category: "Hidden by category"
        case .region: "Doesn't match selected countries or languages"
        case .missingMetadata: "No country or language tags"
        case .scan: "Hidden by a channel scan. Review scan results in Sources."
        }
    }
}

private struct LiveTVOrganizationFailure: View {
    let model: LiveTVPrototypeModel

    var body: some View {
        if model.preferencesIssue != nil {
            SettingsSectionGroup {
                Text("Channel choices couldn't be loaded or saved. Your saved choices have not been replaced.")
                Button("Retry") { model.retryPreferences() }
                    .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            }
        }
    }
}
