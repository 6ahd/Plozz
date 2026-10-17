#if canImport(SwiftUI)
import CoreModels
import CoreUI
import SwiftUI

#if os(tvOS)
struct SettingsLibrariesRow: View {
    let accounts: [Account]
    let isAccountIncluded: (String) -> Bool
    var icon = "rectangle.stack"

    var body: some View {
        SettingsSectionButton(
            title: Text(SettingsCopy.libraries), icon: icon,
            subtitleContent: AnyView(SettingsLibrarySourcesSummary(
                accounts: accounts, isAccountIncluded: isAccountIncluded
            )), route: .myLibraries
        )
    }

    static func watchedServerGroups(
        in accounts: [Account], isAccountIncluded: (String) -> Bool
    ) -> [ServerAccountGroup] {
        SettingsLibrarySourcesSummary.watchedServerGroups(
            in: accounts, isAccountIncluded: isAccountIncluded
        )
    }
}
#endif

/// The added sources this profile watches, independent of library discovery.
public struct SettingsLibrarySourcesSummary: View {
    private let accounts: [Account]
    private let isAccountIncluded: (String) -> Bool

    public init(accounts: [Account], isAccountIncluded: @escaping (String) -> Bool) {
        self.accounts = accounts
        self.isAccountIncluded = isAccountIncluded
    }

    public var body: some View {
        let groups = Self.watchedServerGroups(in: accounts, isAccountIncluded: isAccountIncluded)
        if accounts.isEmpty {
            Text("No servers yet")
        } else if groups.isEmpty {
            Text("Choose what to watch")
        } else {
            #if os(tvOS)
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
            #else
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(groups.prefix(3)), id: \.serverKey) { group in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        ProviderIcon(
                            provider: group.providerKind, size: 16,
                            mediaShareTransport: group.transportKind
                        )
                        .accessibilityHidden(true)
                        Text(verbatim: group.serverName)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if groups.count > 3 {
                    Text("+\(groups.count - 3) more")
                }
            }
            .accessibilityElement(children: .combine)
            #endif
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
