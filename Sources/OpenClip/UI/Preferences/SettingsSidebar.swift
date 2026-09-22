// SettingsSidebar.swift
// OpenClip
//
// The window's table of contents, laid out the way System Settings lays out its own: a search
// field at the top, then three groups of rows with coloured glyph tiles — OpenClip's own pages,
// then what it ships that provides actions, then what the user installed, one row each.
// Selecting a row is the only thing the sidebar does; the router decides what that shows.

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
            tile: .symbol(page.systemImage, tint: page.tint),
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
        case .ai, .decisions: return 0
        case .builtinAction: return 1
        case .customActions: return 2
        case .extensionPackage: return 3
        default: return 4
        }
    }

    /// Whether a row is a package the user installed, which is where the second gap goes: what
    /// OpenClip ships reads as one block, what was installed as another. It is the same line the
    /// tint colours draw — blue above it, a generated colour below.
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

/// What colour a sidebar tile is.
///
/// The app's own settings are drawn the way System Settings draws its rows: a vivid, recognisable
/// colour each — grey for General, black for Appearance, purple for Customize, orange for App
/// Rules, blue for Store. Everything below that group is an action or an extension, and those rows
/// carry no tile at all: they are plain glyphs, the way Finder, Mail and Xcode list their items.
enum SettingsTint {
    /// The settings sections themselves: vivid and distinct, mirroring the reference sidebar.
    static let general = Color(nsColor: .systemGray)
    static let appearance = Color(white: 0.15)
    static let customize = Color.purple
    static let shortcuts = Color.purple
    static let appRules = Color.orange
    static let store = Color.blue
    static let about = Color(nsColor: .systemGray)

    /// Everything OpenClip ships, tracking the system accent color so it matches macOS settings.
    static var openClip: Color {
        Color.accentColor
    }

    /// Hues that read as blue, from cyan through indigo. Reserved.
    static let reservedBlueHues: Range<Int> = 190..<270

    /// A stable colour for an extension's tile, so the same package always gets the same tint —
    /// and never a blue one. Saturated and bright, so an installed package's hero tile reads as
    /// vivid as the system tiles next to it instead of turning muddy.
    static func extensionTint(for packageID: String) -> Color {
        Color(hue: Double(hue(for: packageID)) / 360.0, saturation: 0.74, brightness: 0.88)
    }

    /// The hue an identifier maps to, in degrees, with the reserved band skipped rather than
    /// clamped — clamping would pile every id that hashed into the band onto its two edges.
    /// Pure, so "never blue" is pinned by tests.
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
                    .font(.system(size: size * 0.58, weight: .semibold))
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
        ScrollViewReader { proxy in
            sidebarChrome
                .onAppear { scrollSelectionIntoView(proxy, animated: false) }
                .onChange(of: selection) { _, _ in scrollSelectionIntoView(proxy, animated: true) }
                .onChange(of: query) { _, newValue in
                    // Rows come back when the search is cleared, so reveal the selection again.
                    if newValue.isEmpty { scrollSelectionIntoView(proxy, animated: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openClipPreferencesWindowDidShow)) { _ in
                    // A reused window never fires `onAppear` again, so this is what reveals the
                    // selected row when Settings is reopened.
                    scrollSelectionIntoView(proxy, animated: false)
                }
        }
    }

    @ViewBuilder
    private var sidebarChrome: some View {
        if #available(macOS 26.0, *) {
            // macOS 26 owns this: the field is a real bar, and the system's soft scroll edge
            // effect blurs the rows as they pass beneath it. No hand-rolled material or mask —
            // that backing is what made the strip read as a foreign band.
            sidebarList(includeTopSpacer: false)
                .safeAreaBar(edge: .top) { searchFieldBar }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            ZStack(alignment: .top) {
                sidebarList(includeTopSpacer: true)
                searchHeader
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    /// Brings `selection` on screen. `scrollTo` with no anchor scrolls the minimum needed, so
    /// clicking a row that is already visible does not recenter the list under the pointer.
    private func scrollSelectionIntoView(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let page = selection else { return }
        let scroll = { proxy.scrollTo(page.id) }
        if animated {
            withAnimation(.easeInOut(duration: 0.18)) { scroll() }
        } else {
            // Let the List lay out first: on first appearance the row may not exist yet.
            DispatchQueue.main.async { scroll() }
        }
    }

    /// The rows, shared by both presentations. The top spacer exists only for the pre-26 path,
    /// where the field is overlaid and the rows must start below it; on macOS 26 the bar reserves
    /// its own space.
    private func sidebarList(includeTopSpacer: Bool) -> some View {
        List(selection: $selection) {
            if includeTopSpacer {
                Section {
                    Color.clear
                        .frame(height: 70)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .selectionDisabled()
                }
            }

            if !filteredSystemRows.isEmpty {
                Section {
                    ForEach(filteredSystemRows) { row in
                        rowView(row)
                    }
                }
            }

            // Two sections rather than one, so the gap that separates the settings from
            // what OpenClip ships repeats between what OpenClip ships and what was installed.
            let (bundled, installed) = SettingsSidebarOrder.split(filteredExtensionRows)

            if !bundled.isEmpty {
                Section("Actions") {
                    ForEach(bundled) { row in
                        rowView(row)
                    }
                }
            }

            if !installed.isEmpty {
                Section("Installed") {
                    ForEach(installed) { row in
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

    /// The macOS 26 bar's content: just the field. The system draws the bar's blurred backing and
    /// the soft edge effect that blurs content scrolling under it, so nothing is added here.
    private var searchFieldBar: some View {
        NativeSearchField(
            text: $query,
            placeholder: String(localized: "Search"),
            controlSize: .regular,
            focusRingType: .none
        )
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityLabel(String(localized: "Search settings"))
    }

    private func rowView(_ row: SettingsSidebarRow) -> some View {
        HStack(spacing: 9) {
            switch row.tile {
            case .symbol(let name, let tint):
                SettingsIconTile(systemImage: name, tint: tint, size: 20)
            case .icon(let icon, let tint):
                ExtensionIconTile(icon: icon, tint: tint, size: 20)
            case .bare(let icon):
                ActionIconView(icon: icon, size: 14)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20, alignment: .center)
            }
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .opacity(row.isDisabled ? 0.45 : 1.0)
        .saturation(row.isDisabled ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: row.isDisabled)
        .padding(.vertical, 2)
        .tag(row.page)
        .accessibilityLabel(row.isDisabled ? String(localized: "\(row.title) (Disabled)") : row.title)
    }

    /// A real `NSSearchField`, the control System Settings uses in the same spot,
    /// with its background blurred into the upper window title bar.
    private var searchHeader: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 44)

            NativeSearchField(
                text: $query,
                placeholder: String(localized: "Search"),
                controlSize: .regular,
                focusRingType: .none
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            SidebarVibrancyBackground()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .accessibilityLabel(String(localized: "Search settings"))
    }
}

/// The strip behind the search field draws the very material the `List`'s sidebar already draws,
/// so the two read as one surface. Painting a separate `.ultraThickMaterial` on top of a
/// near-opaque window-background layer produced a lighter band with a visible seam. The gradient
/// mask fades its lower edge so rows dissolve under the field instead of clipping at a hard line.
private struct SidebarVibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        // Behind-window, like the `NavigationSplitView` sidebar itself — in-window is for toolbars
        // and composites over this window's content, which rendered lighter than the sidebar.
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
