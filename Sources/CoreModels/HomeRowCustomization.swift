import Foundation

/// Stable row identity, never a localized heading or a changing recommendation subject.
public enum HomeRowID: Hashable, Codable, Sendable {
    case global(HomeGlobalRow)
    case libraries
    case library(key: String, section: String)

    public static func library(_ key: String, kind: LibraryHomeRowKind) -> Self {
        .library(key: key, section: kind.rawValue)
    }

    public var libraryKey: String? {
        guard case let .library(key, _) = self else { return nil }
        return key
    }

    public var libraryKind: LibraryHomeRowKind? {
        guard case let .library(_, section) = self else { return nil }
        return LibraryHomeRowKind(rawValue: section) ?? .hubs
    }

    public var presentationID: String {
        switch self {
        case let .global(row): return "home-\(row.rawValue)"
        case .libraries: return "home-libraries"
        case let .library(key, section):
            return "home-library-\(key.utf8.count):\(key)-\(section)"
        }
    }
}

/// One arranger entry. Server-authored titles stay content, not localization keys.
public struct HomeRowChoice: Identifiable, Equatable, Sendable {
    public let id: HomeRowID
    public let title: String // l10n:content — provider heading or stable fallback
    public let localizedTitle: LocalizedStringResource?
    public let library: AggregatedLibrary?
    public let isProviderDefault: Bool
    public let isLegacyDefault: Bool

    public init(
        id: HomeRowID, title: String, localizedTitle: LocalizedStringResource? = nil,
        library: AggregatedLibrary? = nil, isProviderDefault: Bool, isLegacyDefault: Bool = true
    ) {
        self.id = id
        self.title = title
        self.localizedTitle = localizedTitle
        self.library = library
        self.isProviderDefault = isProviderDefault
        self.isLegacyDefault = isLegacyDefault
    }

    public static var shared: [Self] {
        HomeGlobalRow.allCases.map {
            Self(id: .global($0), title: $0.rawValue, localizedTitle: $0.title,
                 isProviderDefault: $0 != .recentlyAdded)
        } + [
            Self(id: .libraries, title: "Libraries", localizedTitle: "Libraries",
                 isProviderDefault: true)
        ]
    }

    public static func baseRows(for library: AggregatedLibrary) -> [Self] {
        LibraryHomeRowKind.available(for: library).filter { $0 != .hubs }.map {
            Self(
                id: .library(library.key, kind: $0),
                title: $0.rawValue, localizedTitle: $0.displayName,
                library: library, isProviderDefault: true
            )
        }
    }

    public init(section: LibrarySection, library: AggregatedLibrary) {
        self.init(
            id: .library(key: library.key, section: section.id),
            title: section.title, localizedTitle: section.localizedTitle,
            library: library,
            isProviderDefault: section.isHomeDefault
                ?? (section.id == "recentlyAdded" || section.id == "nextUp" || library.providerKind == .plex),
            isLegacyDefault: section.isLegacyHomeDefault ?? true
        )
    }
}

/// Profile-synced intent. Missing/offline rows retain both order and visibility.
public struct HomeRowCustomization: Codable, Equatable, Sendable {
    public enum Defaults: String, Codable, CaseIterable, Sendable {
        case provider
        case combined
        case legacy

        public var title: LocalizedStringResource {
            switch self {
            case .provider: return "Server defaults"
            case .combined: return "Combined rows"
            case .legacy: return "Previous layout"
            }
        }
    }

    public var defaults: Defaults
    public var order: [HomeRowID]
    public var hidden: Set<HomeRowID>
    public var shown: Set<HomeRowID>

    public init(
        defaults: Defaults = .provider, order: [HomeRowID] = [],
        hidden: Set<HomeRowID> = [], shown: Set<HomeRowID> = []
    ) {
        self.defaults = defaults
        self.order = order
        self.hidden = hidden
        self.shown = shown.subtracting(hidden)
    }

    public func isVisible(_ id: HomeRowID, providerDefault: Bool) -> Bool {
        if hidden.contains(id) { return false }
        if shown.contains(id) { return true }
        switch defaults {
        case .provider, .legacy: return providerDefault
        case .combined: return id.libraryKey == nil
        }
    }

    public func sections(choices: [HomeRowChoice]) -> OrderedVisibilityList.Sections<HomeRowID> {
        OrderedVisibilityList.resolving(
            available: choices.map(\.id), order: order,
            hidden: Set(choices.filter { !isVisible($0.id, providerDefault: $0.isProviderDefault) }.map(\.id))
        )
    }

    public mutating func setVisible(_ visible: Bool, for id: HomeRowID) {
        if visible {
            hidden.remove(id)
            shown.insert(id)
        } else {
            shown.remove(id)
            hidden.insert(id)
        }
    }

    public mutating func apply(
        _ sections: OrderedVisibilityList.Sections<HomeRowID>, choices: [HomeRowChoice]
    ) {
        let available = Set(choices.map(\.id))
        let previous = self.sections(choices: choices)
        var seen = Set<HomeRowID>()
        let edited = sections.combined.filter { available.contains($0) && seen.insert($0).inserted }
        var iterator = edited.makeIterator()
        var result: [HomeRowID] = []
        for id in order {
            if available.contains(id) {
                if let next = iterator.next() { result.append(next) }
            } else {
                result.append(id)
            }
        }
        while let next = iterator.next() { result.append(next) }
        seen.removeAll()
        order = result.filter { seen.insert($0).inserted }
        let enabled = Set(sections.enabled)
        for id in Set(previous.enabled).symmetricDifference(enabled).intersection(available) {
            setVisible(enabled.contains(id), for: id)
        }
        // A saved arrangement also remembers automatically hidden choices, so
        // loading placeholders cannot turn optional rows back on.
        hidden.formUnion(Set(sections.disabled).intersection(available))
        shown.subtract(hidden)
    }

    private enum CodingKeys: String, CodingKey {
        case defaults, order, hidden, shown
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(defaults, forKey: .defaults)
        try values.encode(order, forKey: .order)
        try values.encode(hidden.sorted { $0.presentationID < $1.presentationID }, forKey: .hidden)
        try values.encode(shown.sorted { $0.presentationID < $1.presentationID }, forKey: .shown)
    }
}
