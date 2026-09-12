// SettingsRouter.swift
// OpenClip
//
// One router owns what the Preferences window is showing, and the sidebar is its table of contents.
//
// Before this, a setting's depth decided its container: top-level settings were panes, an action's
// settings were an `.applicationDefined` NSPopover floating over the list, the icon picker was a
// popover on top of that popover, and an AI prompt was a sheet that dimmed all three. Nothing in
// the sidebar ever moved, so the window could not tell you what you were editing, and the only way
// back was to guess which layer to close first.
//
// Vorssaint's settings are the counter-example: a `SettingsRouter` singleton holds the current
// `SettingsPage`, a `NavigationSplitView` renders the sidebar from it, and every feature — plus
// cross-cutting pages for keyboard shortcuts and permissions — is a destination in that one list.
// Depth becomes a route, not a new window.

import SwiftUI
import Core

/// Everything the Preferences window can show.
///
/// The top-level cases are the sidebar's rows. `.action` is a *child* route: it is reached from the
/// Actions list, and the sidebar shows it indented under Actions while it is current, so the window
/// always says where you are.
public enum SettingsPage: Hashable, Identifiable, Sendable {
    case general
    case appearance
    case actions
    /// A single action's settings, filling the detail column.
    case action(id: String)
    case shortcuts
    case ai
    case store
    case appRules
    case about

    public var id: String {
        switch self {
        case .general: return "general"
        case .appearance: return "appearance"
        case .actions: return "actions"
        case .action(let id): return "action:\(id)"
        case .shortcuts: return "shortcuts"
        case .ai: return "ai"
        case .store: return "store"
        case .appRules: return "appRules"
        case .about: return "about"
        }
    }

    /// Rows of the sidebar, in order. `.action` is deliberately absent: it only appears while one
    /// is being configured.
    public static let sidebarPages: [SettingsPage] = [
        .general, .appearance, .actions, .shortcuts, .ai, .store, .appRules, .about
    ]

    public var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .appearance: return String(localized: "Appearance")
        case .actions: return String(localized: "Actions")
        case .action: return String(localized: "Configure Action")
        case .shortcuts: return String(localized: "Shortcuts")
        case .ai: return String(localized: "AI")
        case .store: return String(localized: "Store")
        case .appRules: return String(localized: "App Rules")
        case .about: return String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .actions: return "bolt.horizontal.fill"
        case .action: return "slider.horizontal.3"
        case .shortcuts: return "keyboard.fill"
        case .ai: return "sparkles"
        case .store: return "bag.fill"
        case .appRules: return "shield.checkerboard"
        case .about: return "info.circle.fill"
        }
    }

    /// Sidebar symbol tint, matching System Settings' coloured glyph tiles.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .actions, .action: return .orange
        case .shortcuts: return .green
        case .ai: return .purple
        case .store: return .blue
        case .appRules: return .indigo
        case .about: return .teal
        }
    }

    /// Terms the sidebar search matches, beyond the title. Keeps "hotkey" finding Shortcuts and
    /// "api key" finding AI, which is the whole point of searching settings.
    var searchKeywords: [String] {
        switch self {
        case .general: return ["startup", "launch", "login", "paste", "clipboard"]
        case .appearance: return ["theme", "dark", "light", "icon"]
        case .actions, .action: return ["extension", "group", "enable", "order"]
        case .shortcuts: return ["hotkey", "keyboard", "alias", "shortcut", "key"]
        case .ai: return ["model", "api key", "prompt", "openai", "ollama", "cli", "claude"]
        case .store: return ["extensions", "install", "catalog"]
        case .appRules: return ["apps", "exclude", "allow", "block", "rules"]
        case .about: return ["version", "update", "licence", "license"]
        }
    }
}

/// The one place that knows what the window is showing.
///
/// A shared object because the Actions list's rows are hosted in an `NSOutlineView`, which rebuilds
/// its cell views on every model change: a row cannot own the route it navigates to.
@MainActor
public final class SettingsRouter: ObservableObject {
    public static let shared = SettingsRouter()

    @Published public var page: SettingsPage = .general

    /// The action whose page was last opened, kept after leaving it so the sidebar can offer the
    /// way back to it — the same way Vorssaint keeps a configured feature reachable.
    @Published public private(set) var lastConfiguredActionID: String?

    private init() {}

    public func show(_ page: SettingsPage) {
        if case .action(let id) = page {
            lastConfiguredActionID = id
        }
        self.page = page
    }

    /// Leaves an action's page for the list it came from.
    public func backToActions() {
        page = .actions
    }

    /// Pages whose titles or keywords match `query`, for the sidebar's filter.
    public func matches(_ query: String) -> [SettingsPage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return SettingsPage.sidebarPages }
        return SettingsPage.sidebarPages.filter { page in
            page.title.lowercased().contains(needle)
                || page.searchKeywords.contains { $0.contains(needle) }
        }
    }
}
