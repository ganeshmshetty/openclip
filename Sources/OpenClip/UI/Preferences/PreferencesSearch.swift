import Foundation

enum GeneralSearchTarget {
    static let appearAutomatically = "general.appearAutomatically"
    static let holdMouseToTrigger = "general.holdMouseToTrigger"
    static let commandPalette = "general.commandPalette"
    static let captureText = "general.captureText"
    static let captureTextAutoCopy = "general.captureTextAutoCopy"
    static let saveLocation = "general.saveLocation"
    static let playCopySound = "general.playCopySound"
    static let showMenuBarIcon = "general.showMenuBarIcon"
    static let startAtLogin = "general.startAtLogin"
    static let accessibilityAccess = "general.accessibilityAccess"
    static let screenRecordingAccess = "general.screenRecordingAccess"
    static let all = [
        appearAutomatically, holdMouseToTrigger, commandPalette, captureText,
        captureTextAutoCopy, saveLocation, playCopySound, showMenuBarIcon, startAtLogin, accessibilityAccess, screenRecordingAccess
    ]
}

enum PreferencesSearchSection: Hashable, Sendable {
    case settings
    case actions
}

enum PreferencesSearchTarget: Hashable, Sendable {
    case page([SettingsPage])
    case generalControl(id: String)
}

struct PreferencesSearchEntry: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let breadcrumb: String
    let aliases: [String]
    let target: PreferencesSearchTarget
    let section: PreferencesSearchSection

    static func page(
        id: String,
        title: String,
        breadcrumb: String,
        aliases: [String] = [],
        path: [SettingsPage],
        section: PreferencesSearchSection = .settings
    ) -> Self {
        Self(id: id, title: title, breadcrumb: breadcrumb, aliases: aliases, target: .page(path), section: section)
    }

    static func generalControl(id: String, title: String, aliases: [String] = []) -> Self {
        Self(
            id: "general-control:\(id)",
            title: title,
            breadcrumb: String(localized: "General"),
            aliases: aliases,
            target: .generalControl(id: id),
            section: .settings
        )
    }
}

enum PreferencesSearch {
    /// Arrow navigation includes Store but never selects it implicitly on an empty result set.
    static func movedSelection(from current: String?, in ids: [String], direction: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return ids.first }
        return ids[min(max(index + direction, 0), ids.count - 1)]
    }

    private struct RankedEntry {
        let entry: PreferencesSearchEntry
        let rank: Int
        let offset: Int
    }

    private struct DedupeKey: Hashable {
        let target: PreferencesSearchTarget
        let normalizedTitle: String
    }

    /// Normalizes the catalog when it changes, rather than on every keystroke or row update.
    struct Index {
        private struct IndexedEntry {
            let entry: PreferencesSearchEntry
            let title: String
            let fields: [String]
        }

        private let entries: [IndexedEntry]

        init(entries: [PreferencesSearchEntry]) {
            self.entries = entries.map { entry in
                IndexedEntry(
                    entry: entry,
                    title: normalize(entry.title),
                    fields: entry.aliases.filter { !$0.isEmpty }.map(normalize)
                )
            }
        }

        func results(query: String) -> [PreferencesSearchEntry] {
            let normalizedQuery = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !normalizedQuery.isEmpty else { return [] }
            let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
            // Short queries are deliberate prefixes; longer queries may match within a name.
            func matches(_ name: String) -> Bool {
                if normalizedQuery.count <= 2 { return name.hasPrefix(normalizedQuery) }
                return tokens.allSatisfy { name.contains($0) }
            }
            var seen = Set<DedupeKey>()
            let ranked = entries.enumerated().compactMap { offset, indexed -> RankedEntry? in
                let titleMatches = matches(indexed.title)
                let aliasMatches = indexed.fields.contains(where: matches)
                guard titleMatches || aliasMatches else { return nil }
                let entry = indexed.entry
                guard seen.insert(DedupeKey(target: entry.target, normalizedTitle: indexed.title)).inserted else { return nil }
                let rank: Int
                if indexed.title == normalizedQuery { rank = 0 }
                else if indexed.fields.contains(normalizedQuery) { rank = 1 }
                else if indexed.title.hasPrefix(normalizedQuery) { rank = 2 }
                else if indexed.fields.contains(where: { $0.hasPrefix(normalizedQuery) }) { rank = 3 }
                else { rank = titleMatches ? 4 : 5 }
                return RankedEntry(entry: entry, rank: rank, offset: offset)
            }
            return Array(ranked.sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.offset < $1.offset
            }.prefix(6).map(\.entry))
        }
    }

    static func results(in entries: [PreferencesSearchEntry], query: String) -> [PreferencesSearchEntry] {
        Index(entries: entries).results(query: query)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
