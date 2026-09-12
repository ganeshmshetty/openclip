// SettingsSidebar.swift
// OpenClip
//
// The window's table of contents, laid out the way System Settings lays out its own: a search
// field at the top, then two groups of rows with coloured glyph tiles — OpenClip's own pages
// first, then everything that provides actions, one row each. Selecting a row is the only thing
// the sidebar does; the router decides what that shows.

import SwiftUI
import Core

// MARK: - Rows

/// One sidebar row, resolved to strings so the filter can run over it without touching the models.
struct SettingsSidebarRow: Identifiable {
    enum Tile {
        case symbol(String, tint: Color)
        case icon(ActionIcon, tint: Color)
    }

    let page: SettingsPage
    let title: String
    let keywords: [String]
    let tile: Tile

    var id: String { page.id }

    init(page: SettingsPage, title: String, keywords: [String] = [], tile: Tile) {
        self.page = page
        self.title = title
        self.keywords = keywords
        self.tile = tile
    }

    /// A system page row: title, glyph and search terms come from the page itself.
    init(systemPage page: SettingsPage) {
        self.init(
            page: page,
            title: page.staticTitle ?? page.id,
            keywords: page.searchKeywords,
            tile: .symbol(page.systemImage, tint: page.tint)
        )
    }

    /// Whether the row answers `query`. Every word of the query has to appear somewhere in the
    /// title or the keywords, so "api key" finds AI and "jwt verify" finds the JWT extension.
    func matches(_ query: String) -> Bool {
        let words = Self.words(in: query)
        guard !words.isEmpty else { return true }
        let haystack = ([title] + keywords).map { $0.lowercased() }
        return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
    }

    static func words(in query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

/// The order of the sidebar's second group: what OpenClip ships first, then what the user
/// installed. Inside a rank the rows read alphabetically, so a name is still where you expect it.
enum SettingsSidebarOrder {
    /// Lower sorts first. AI leads because it is the headline feature; the built-in actions
    /// follow; the user's own actions close out what came with the app or was written here; and
    /// installed extensions come last, because they are the part that changes.
    static func rank(of page: SettingsPage) -> Int {
        switch page {
        case .ai: return 0
        case .builtinAction: return 1
        case .customActions: return 2
        case .extensionPackage: return 3
        default: return 4
        }
    }

    static func sorted(_ rows: [SettingsSidebarRow]) -> [SettingsSidebarRow] {
        rows.sorted { left, right in
            let leftRank = rank(of: left.page)
            let rightRank = rank(of: right.page)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }
}

enum SettingsSidebarFilter {
    static func filter(_ rows: [SettingsSidebarRow], query: String) -> [SettingsSidebarRow] {
        guard !SettingsSidebarRow.words(in: query).isEmpty else { return rows }
        return rows.filter { $0.matches(query) }
    }
}

/// A stable colour for an extension's tile, so the same package always gets the same tint.
enum ExtensionTint {
    static func color(for packageID: String) -> Color {
        var hash = 0
        for byte in packageID.utf8 {
            hash = (hash &* 31 &+ Int(byte)) % 360
        }
        return Color(hue: Double(max(hash, 0)) / 360.0, saturation: 0.58, brightness: 0.70)
    }
}

// MARK: - Tiles

/// The coloured rounded square with a white glyph that System Settings puts in front of every
/// sidebar row.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The same tile for an extension, drawing whatever icon the package ships: a symbol, a template
/// SVG, a favicon, or a text glyph.
struct ExtensionIconTile: View {
    let icon: ActionIcon
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                switch icon {
                case .text(let text):
                    Text(String(text.trimmingCharacters(in: .whitespaces).prefix(2)))
                        .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                default:
                    ActionIconView(icon: icon, size: size * 0.56)
                        .foregroundStyle(.white)
                        .frame(width: size * 0.7, height: size * 0.7)
                        .clipped()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SettingsTileBackground: View {
    let tint: Color
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.92), tint],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                // The specular highlight the system tiles carry: brighter along the top edge.
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            }
    }
}

// MARK: - Sidebar

@MainActor
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?
    @Binding var query: String
    let systemRows: [SettingsSidebarRow]
    let extensionRows: [SettingsSidebarRow]

    private var filteredSystemRows: [SettingsSidebarRow] {
        SettingsSidebarFilter.filter(systemRows, query: query)
    }

    private var filteredExtensionRows: [SettingsSidebarRow] {
        SettingsSidebarFilter.filter(extensionRows, query: query)
    }

    private var hasResults: Bool {
        !filteredSystemRows.isEmpty || !filteredExtensionRows.isEmpty
    }

    var body: some View {
        // The field is stacked above the list rather than laid over it as a safe-area inset: an
        // inset lets the rows scroll *under* the field, so a row passed behind it while the
        // scroller stopped below it. Stacked, the field owns its strip and nothing crosses it.
        VStack(spacing: 0) {
            searchField

            List(selection: $selection) {
                if !filteredSystemRows.isEmpty {
                    Section {
                        ForEach(filteredSystemRows) { row in
                            rowView(row)
                        }
                    }
                }

                if !filteredExtensionRows.isEmpty {
                    Section {
                        ForEach(filteredExtensionRows) { row in
                            rowView(row)
                        }
                    }
                }

                if !hasResults {
                    Section {
                        Text("No Results")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .selectionDisabled()
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func rowView(_ row: SettingsSidebarRow) -> some View {
        HStack(spacing: 9) {
            switch row.tile {
            case .symbol(let name, let tint):
                SettingsIconTile(systemImage: name, tint: tint)
            case .icon(let icon, let tint):
                ExtensionIconTile(icon: icon, tint: tint)
            }
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .tag(row.page)
        .accessibilityLabel(row.title)
    }

    /// A real `NSSearchField`, the control System Settings uses in the same spot.
    private var searchField: some View {
        NativeSearchField(
            text: $query,
            placeholder: String(localized: "Search"),
            controlSize: .regular
        )
        .frame(height: 24)
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .accessibilityLabel(String(localized: "Search settings"))
    }
}
