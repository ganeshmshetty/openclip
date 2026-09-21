// SettingsSidebar.swift
// OpenClip
//
// The window's table of contents:
// - Sits directly on the window background (no card, border or shadow).
// - Top-left traffic lights space, then a translucent capsule search field.
// - Fixed width (~216pt), ~30pt pitch rows.
// - Every row has a ~20pt rounded-square icon tile with a white glyph on a colored fill.
// - Selection: subtle translucent rounded highlight (~11% opacity, ~10pt radius), NOT accent color.
// - Dim, unobtrusive "Actions" group label with extra vertical spacing.
// - Hidden scroll indicators, no separator lines.

import SwiftUI
import AppKit
import Core

// MARK: - Rows

/// One sidebar row, resolved to strings so the filter can run over it without touching the models.
struct SettingsSidebarRow: Identifiable {
    enum Tile {
        case symbol(String, tint: Color)
        case icon(ActionIcon, tint: Color)
        case bare(ActionIcon)
    }

    let page: SettingsPage
    let title: String
    let keywords: [String]
    let tile: Tile
    let isDisabled: Bool

    var id: String { page.id }

    init(page: SettingsPage, title: String, keywords: [String] = [], tile: Tile, isDisabled: Bool = false) {
        self.page = page
        self.title = title
        self.keywords = keywords
        self.tile = tile
        self.isDisabled = isDisabled
    }

    /// A system page row: title, glyph and search terms come from the page itself.
    init(systemPage page: SettingsPage, isDisabled: Bool = false) {
        self.init(
            page: page,
            title: page.staticTitle ?? page.id,
            keywords: page.searchKeywords,
            tile: .symbol(page.systemImage, tint: SettingsDesignTokens.iconTileColor(for: page)),
            isDisabled: isDisabled
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

    /// Whether a row is a package the user installed, which is where the second gap goes: what
    /// OpenClip ships reads as one block, what was installed as another.
    static func isInstalledExtension(_ page: SettingsPage) -> Bool {
        if case .extensionPackage = page { return true }
        return false
    }

    /// The second group cut in two at that line, each half still in `sorted` order.
    static func split(
        _ rows: [SettingsSidebarRow]
    ) -> (bundled: [SettingsSidebarRow], installed: [SettingsSidebarRow]) {
        (rows.filter { !isInstalledExtension($0.page) }, rows.filter { isInstalledExtension($0.page) })
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

/// Stable palette and hash-based tints for extensions.
enum SettingsTint {
    static let general = Color(nsColor: .systemGray)
    static let appearance = Color(red: 0.95, green: 0.35, blue: 0.60)
    static let customize = Color(red: 0.65, green: 0.35, blue: 0.95)
    static let shortcuts = Color(red: 0.68, green: 0.35, blue: 0.98)
    static let appRules = Color(red: 0.98, green: 0.52, blue: 0.12)
    static let store = Color(red: 0.05, green: 0.52, blue: 0.98)
    static let about = Color(red: 0.20, green: 0.78, blue: 0.42)
    static let neutral = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0)
        } else {
            return NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0)
        }
    }))

    static var openClip: Color {
        Color.accentColor
    }

    static let reservedBlueHues: Range<Int> = 190..<270

    static func extensionTint(for packageID: String) -> Color {
        Color(hue: Double(hue(for: packageID)) / 360.0, saturation: 0.74, brightness: 0.88)
    }

    static func hue(for packageID: String) -> Int {
        var hash = 0
        for byte in packageID.utf8 {
            hash = (hash &* 31 &+ Int(byte)) % 360
        }
        let available = 360 - reservedBlueHues.count
        var value = ((hash % available) + available) % available
        if value >= reservedBlueHues.lowerBound {
            value += reservedBlueHues.count
        }
        return value
    }
}

// MARK: - Tiles

/// The ~20pt coloured rounded square with a white glyph on front of every sidebar row.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = SettingsDesignTokens.iconTileSize

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The same tile for an extension, drawing whatever icon the package ships.
struct ExtensionIconTile: View {
    let icon: ActionIcon
    let tint: Color
    var size: CGFloat = SettingsDesignTokens.iconTileSize

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                switch icon {
                case .text(let text):
                    Text(String(text.trimmingCharacters(in: .whitespaces).prefix(2)))
                        .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                default:
                    ActionIconView(icon: icon, size: size * 0.58)
                        .foregroundStyle(.white)
                        .frame(width: size * 0.72, height: size * 0.72)
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
        RoundedRectangle(cornerRadius: SettingsDesignTokens.iconTileRadius(for: size), style: .continuous)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.96), tint],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
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
    @State private var hoveredRowID: String? = nil

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
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Top area: space for traffic lights + capsule search field
                VStack(spacing: 12) {
                    Color.clear
                        .frame(height: 38)

                    searchField
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

                // Scrollable rows with hidden indicators and no separator lines
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !filteredSystemRows.isEmpty {
                            ForEach(filteredSystemRows) { row in
                                rowView(row)
                                    .id(row.page.id)
                            }
                        }

                        let (bundled, installed) = SettingsSidebarOrder.split(filteredExtensionRows)

                        if !bundled.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Actions"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SettingsDesignTokens.secondaryText.opacity(0.7))
                                    .padding(.leading, 10)
                                    .padding(.top, SettingsDesignTokens.sidebarGroupSpacing)
                                    .padding(.bottom, 4)

                                ForEach(bundled) { row in
                                    rowView(row)
                                        .id(row.page.id)
                                }
                            }
                        }

                        if !installed.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Installed"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SettingsDesignTokens.secondaryText.opacity(0.7))
                                    .padding(.leading, 10)
                                    .padding(.top, SettingsDesignTokens.sidebarGroupSpacing)
                                    .padding(.bottom, 4)

                                ForEach(installed) { row in
                                    rowView(row)
                                        .id(row.page.id)
                                }
                            }
                        }

                        if !hasResults {
                            Text(String(localized: "No Results"))
                                .font(.callout)
                                .foregroundStyle(SettingsDesignTokens.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
            }
            .frame(width: SettingsDesignTokens.sidebarWidth)
            .background(Color.clear)
            .onAppear { scrollSelectionIntoView(proxy, animated: false) }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty { scrollSelectionIntoView(proxy, animated: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openClipPreferencesWindowDidShow)) { _ in
                scrollSelectionIntoView(proxy, animated: false)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                .padding(.leading, 8)

            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(SettingsDesignTokens.primaryText)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 26)
        .background(
            Capsule()
                .fill(SettingsDesignTokens.sidebarSearchBackground)
        )
        .overlay(
            Capsule()
                .strokeBorder(SettingsDesignTokens.sidebarSearchBorder, lineWidth: 0.5)
        )
    }

    private func rowView(_ row: SettingsSidebarRow) -> some View {
        let isSelected = selection == row.page
        let isHovered = hoveredRowID == row.id && !isSelected

        return Button {
            selection = row.page
        } label: {
            HStack(spacing: 10) {
                switch row.tile {
                case .symbol(let name, let tint):
                    SettingsIconTile(systemImage: name, tint: tint, size: SettingsDesignTokens.iconTileSize)
                case .icon(let icon, let tint):
                    ExtensionIconTile(icon: icon, tint: tint, size: SettingsDesignTokens.iconTileSize)
                case .bare(let icon):
                    ActionIconView(icon: icon, size: 14)
                        .foregroundStyle(isSelected ? SettingsDesignTokens.primaryText : SettingsDesignTokens.secondaryText)
                        .frame(width: SettingsDesignTokens.iconTileSize, height: SettingsDesignTokens.iconTileSize, alignment: .center)
                }

                Text(row.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: SettingsDesignTokens.sidebarRowPitch)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.sidebarSelectionRadius, style: .continuous)
                    .fill(isSelected ? SettingsDesignTokens.selectedRowBackground : (isHovered ? SettingsDesignTokens.hoveredRowBackground : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredRowID = row.id
            } else if hoveredRowID == row.id {
                hoveredRowID = nil
            }
        }
        .opacity(row.isDisabled ? 0.45 : 1.0)
        .saturation(row.isDisabled ? 0.5 : 1.0)
        .tag(row.page)
    }

    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let page = selection else { return }
        let scroll = { proxy.scrollTo(page.id) }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) { scroll() }
        } else {
            DispatchQueue.main.async { scroll() }
        }
    }
}
