#if os(tvOS)
import CoreModels
import CoreUI
import SwiftUI

/// The added sources this profile watches, independent of library discovery.
struct SettingsLibrariesRow: View {
    let accounts: [Account]
    let isAccountIncluded: (String) -> Bool
    var icon = "rectangle.stack"

    var body: some View {
        SettingsSectionButton(
            title: Text(SettingsCopy.libraries), icon: icon,
            subtitleContent: AnyView(signedInStrip), route: .myLibraries
        )
    }

    @ViewBuilder private var signedInStrip: some View {
        let groups = Self.watchedServerGroups(in: accounts, isAccountIncluded: isAccountIncluded)
        if accounts.isEmpty {
            Text("No servers yet")
        } else if groups.isEmpty {
            Text("Choose what to watch")
        } else {
            HStack(alignment: .center, spacing: 10) {
                let visible = Array(groups.prefix(3))
                let overflow = groups.count - visible.count
                ForEach(Array(visible.enumerated()), id: \.element.serverKey) { index, group in
                    if index > 0 { Text(verbatim: "·") }
                    HStack(spacing: 8) {
                        ProviderIcon(
                            provider: group.providerKind, size: 24,
                            mediaShareTransport: group.transportKind
                        )
                        .scaleEffect(1.3)
                        .padding(.horizontal, 4)
                        Text(verbatim: group.serverName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }
                if overflow > 0 {
                    Text("· +\(overflow) more")
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func watchedServerGroups(
        in accounts: [Account], isAccountIncluded: (String) -> Bool
    ) -> [ServerAccountGroup] {
        serverGroups(from: accounts).filter { group in
            group.accounts.contains { isAccountIncluded($0.id) }
        }
    }
}
#endif
