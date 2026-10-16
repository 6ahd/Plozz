#if os(tvOS)
import CoreModels
import CoreUI
import SwiftUI

/// Observe discovery in this row, never in the root Settings focus hierarchy.
struct SettingsLibrariesRow: View {
    let libraries: DiscoveredLibrariesStore
    let visibility: HomeLibraryVisibilityModel
    let accounts: [Account]
    let isAccountIncluded: (String) -> Bool
    var icon = "rectangle.stack"
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsSectionButton(
            title: Text(SettingsCopy.libraries), icon: icon,
            subtitle: summary, route: .myLibraries
        )
    }

    private var summary: Text? {
        guard case let .loaded(discovered) = libraries.state else { return nil }
        let names = Self.names(
            in: discovered,
            accountIDs: Set(accounts.filter { isAccountIncluded($0.id) }.map(\.id)),
            visibility: visibility.visibility, locale: locale
        )
        guard !names.isEmpty else { return nil }
        return Text(verbatim: names.formatted(.list(type: .and).locale(locale)))
    }

    static func names(
        in libraries: [AggregatedLibrary],
        accountIDs: Set<String>,
        visibility: HomeLibraryVisibility,
        locale: Locale
    ) -> [String] {
        var seen = Set<String>()
        return libraries.compactMap { library in
            guard accountIDs.contains(library.accountID), visibility.isEnabled(library.key),
                  !library.isRetiredCollectionShortcut else { return nil }
            let name = library.library.displayName(in: locale)
            return seen.insert(name).inserted ? name : nil
        }
    }
}
#endif
