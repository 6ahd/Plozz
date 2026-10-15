#if os(tvOS)
import CoreUI
import SwiftUI

struct SettingsFormLayout: View {
    let title: Text
    let rows: [SettingsSplitRow]
    var showsBack = false
    @Environment(SettingsNavigationModel.self) private var navigation: SettingsNavigationModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsFormHeader(title: title, showsBack: showsBack)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SettingsFormRow(row: row, isEntry: index == 0)
                        .disabled(index > 0 && navigation?.focusInDetail == false)
                        .id(row.id)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
        .toggleStyle(SettingsSwitchToggleStyle())
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct SettingsFormHeader: View {
    let title: Text
    let showsBack: Bool
    var route: SettingsRoute?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 24) {
            if showsBack {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .settingsWorkspaceEntry(route: route)
            }
            title.font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

private struct SettingsFormRow: View {
    let row: SettingsSplitRow
    let isEntry: Bool

    var body: some View {
        content
            .settingsWorkspaceEntry(isEntry)
    }

    @ViewBuilder private var content: some View {
        if let route = row.route {
            NavigationLink(value: route) {
                SettingsFormLinkLabel(row: row)
            }
            .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            .accessibilityIdentifier("settings-page-\(row.id)")
        } else if row.presentation == .page {
            NavigationLink {
                SettingsFormRowPage(row: row)
            } label: {
                SettingsFormLinkLabel(row: row)
            }
            .buttonStyle(SettingsFocusButtonStyle(size: .contained))
            .accessibilityIdentifier("settings-page-\(row.id)")
        } else {
            SettingsFormGroup(title: row.title, description: row.description) {
                row.detail()
            }
            .accessibilityIdentifier("settings-group-\(row.id)")
        }
    }
}

struct SettingsFormGroup<Content: View>: View {
    let title: Text
    var description: Text?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.headline)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 24, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .settingsGroupSurface(cornerRadius: 28)
            if let description {
                description
                    .settingsHelperText()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct SettingsFormLinkLabel: View {
    let row: SettingsSplitRow

    var body: some View {
        HStack(spacing: 16) {
            row.title
                .font(.callout.weight(.medium))
            Spacer(minLength: 16)
            row.summary?.font(.callout).settingsRowSecondary()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .settingsRowSecondary()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsGroupSurface(cornerRadius: 20)
    }
}

struct SettingsFormRowPage: View {
    let row: SettingsSplitRow
    var showsBack = true
    var route: SettingsRoute?
    @State private var navigation = SettingsDetailNavigation()

    var body: some View {
        if let children = row.childRows {
            SettingsFormLayout(title: row.title, rows: children(), showsBack: showsBack)
        } else if let subpage = row.subpage {
            SettingsDetailPages(navigation: navigation) {
                SettingsFormRowContent(row: row, showsBack: showsBack, route: route)
            } detail: {
                subpage.content()
            }
        } else {
            SettingsFormRowContent(row: row, showsBack: showsBack, route: route)
        }
    }
}

private struct SettingsFormRowContent: View {
    let row: SettingsSplitRow
    let showsBack: Bool
    let route: SettingsRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsFormHeader(title: row.title, showsBack: showsBack, route: route)
                row.detail()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let description = row.description {
                    description.settingsHelperText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .scrollClipDisabled()
        .toggleStyle(SettingsSwitchToggleStyle())
        .toolbar(.hidden, for: .tabBar)
    }
}
#endif
