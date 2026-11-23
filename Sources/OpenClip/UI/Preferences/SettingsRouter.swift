// SettingsRouter.swift
// OpenClip
//
// One object owns what the Settings window shows: a path of pages and the history of paths visited,
// so the toolbar's back and forward arrows work like System Settings'. Popovers and sheets are pages
// in this path too; depth is a route the window's chrome can see and undo.
//
// A shared object because the navigating rows live in an `NSOutlineView`, which rebuilds its cell
// views on every model change, so a row cannot own the route it points at.

import SwiftUI
import Combine
import Core

/// Everything the Settings window can show. Pages after the sidebar group are reached from a sidebar page.
public enum SettingsPage: Hashable, Identifiable, Sendable {
    // Sidebar — OpenClip
    case general
    case appearance
    /// The popup bar's layout: order and custom groups. Each action's own settings live on its page.
    case customize
    case shortcuts
    case appRules
    case store
    case about

    // Sidebar — the second group: AI, built-in actions, extensions, then custom actions.
    case ai
    case extensionPackage(id: String)
    /// A built-in action's settings (Copy, Search, Calculate, …), as its own sidebar row.
    case builtinAction(id: String)
    /// The user's own Open URL / Text Snippet / Shell Script actions.
    case customActions

    // Pages reached from a sidebar page.
    /// One action's settings, or one group's when the id names a group.
    case action(id: String)
    case newCustomAction(kind: String? = nil)
    case newGroup(memberIDs: [String])
    /// The icon chooser; writes to `SettingsRouter.iconTarget`. The token keeps consecutive choosers distinct.
    case iconPicker(token: Int)
    case aiPreset(id: String)
    case aiNewPreset
    case addApplication

    public var id: String {
        switch self {
        case .general: return "general"
        case .appearance: return "appearance"
        case .customize: return "customize"
        case .shortcuts: return "shortcuts"
        case .appRules: return "appRules"
        case .store: return "store"
        case .about: return "about"
        case .ai: return "ai"
        case .extensionPackage(let id): return "extension:\(id)"
        case .builtinAction(let id): return "builtin:\(id)"
        case .customActions: return "customActions"
        case .action(let id): return "action:\(id)"
        case .newCustomAction(let kind): return "newCustomAction:\(kind ?? "")"
        case .newGroup: return "newGroup"
        case .iconPicker(let token): return "iconPicker:\(token)"
        case .aiPreset(let id): return "aiPreset:\(id)"
        case .aiNewPreset: return "aiNewPreset"
        case .addApplication: return "addApplication"
        }
    }

    /// The sidebar's first group, in order.
    public static let systemPages: [SettingsPage] = [
        .general, .appearance, .customize, .ai, .appRules, .store, .about
    ]

    /// True for pages the sidebar lists; false for pages reached from one of them.
    public var isSidebarPage: Bool {
        switch self {
        case .general, .appearance, .customize, .shortcuts, .ai, .appRules, .store, .about:
            return true
        case .extensionPackage, .builtinAction, .customActions,
             .action, .newCustomAction, .newGroup, .iconPicker, .aiPreset, .aiNewPreset, .addApplication:
            return false
        }
    }

    /// The title for pages whose title does not depend on data. An action's page is titled after
    /// the action, an extension's after the extension; those are resolved by the window.
    public var staticTitle: String? {
        switch self {
        case .general: return String(localized: "General")
        case .appearance: return String(localized: "Customize")
        case .customize: return String(localized: "Actions")
        case .shortcuts: return String(localized: "Shortcuts")
        case .appRules: return String(localized: "App Rules")
        case .store: return String(localized: "Store")
        case .about: return String(localized: "About")
        case .ai: return String(localized: "AI")
        case .newCustomAction: return String(localized: "New Custom Action")
        case .newGroup: return String(localized: "New Group")
        case .iconPicker: return String(localized: "Choose Icon")
        case .aiNewPreset: return String(localized: "New AI Action")
        case .addApplication: return String(localized: "Add Application")
        case .customActions: return String(localized: "Custom Actions")
        case .extensionPackage, .builtinAction, .action, .aiPreset: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "slider.horizontal.3"
        case .customize: return "square.stack.3d.up.fill"
        case .shortcuts: return "command"
        case .appRules: return "shield.checkered"
        case .store: return "archivebox.fill"
        case .about: return "info.circle.fill"
        case .ai: return "sparkle"
        case .extensionPackage: return "puzzlepiece.extension.fill"
        case .builtinAction: return "bolt.fill"
        case .customActions: return "plus"
        case .action: return "slider.horizontal.3"
        case .newCustomAction: return "plus.circle.fill"
        case .newGroup: return "folder.fill.badge.plus"
        case .iconPicker: return "photo.on.rectangle"
        case .aiPreset, .aiNewPreset: return "text.bubble.fill"
        case .addApplication: return "app.badge.checkmark"
        }
    }

    /// Fixed tile colour for app settings pages; action and extension pages use a plain glyph.
    var tint: Color {
        SettingsDesignTokens.iconTileColor(for: self)
    }

    /// Terms the sidebar search matches besides the title, so "hotkey" finds Shortcuts and
    /// "api key" finds AI. Extension rows add their own keywords from the manifest.
    var searchKeywords: [String] {
        switch self {
        case .general: return ["startup", "launch", "login", "menu bar", "trigger", "hotkey", "permission", "accessibility", "paste", "copy", "preview", "command palette", "show command palette", "search button"]
        case .appearance: return ["appearance", "theme", "dark", "light", "glass", "popup", "preview", "customize", "behavior", "scale", "position", "suggested", "suggested actions", "action suggestions", "suggestions", "contextual", "contextual actions", "placement", "bar position", "suggestion position", "pill"]
        case .customize: return ["actions", "popup bar", "order", "reorder", "arrange", "group", "groups", "layout", "install", "shortcuts", "hotkey", "keyboard", "alias", "shortcut", "key", "binding"]
        case .shortcuts: return ["hotkey", "keyboard", "alias", "shortcut", "key", "binding"]
        case .appRules: return ["apps", "exclude", "allow", "block", "rules", "disable", "per-app"]
        case .store: return ["extensions", "clips", "install", "catalog", "browse", "download"]
        case .about: return ["version", "update", "licence", "license", "logs", "diagnostics", "github"]
        case .ai:
            var keywords = ["model", "api key", "prompt", "openai", "claude", "gemini", "ollama", "cli", "local", "cloud", "rewrite", "summarize"]
            if AppleIntelligenceAvailability.isSupported {
                keywords.append("apple intelligence")
            }
            return keywords
        case .customActions: return ["custom", "snippet", "script", "shell", "url", "open url", "text snippet", "my actions"]
        case .extensionPackage, .builtinAction, .action, .newCustomAction, .newGroup, .iconPicker, .aiPreset, .aiNewPreset, .addApplication:
            return []
        }
    }
}

/// An inline message the window shows instead of an alert. A confirmation carries the work it would do,
/// so the page that asked keeps owning it; the banner only draws the question and button.
@MainActor
public struct SettingsNotice: Identifiable {
    public enum Style: Sendable, Equatable {
        case info
        case error
        /// A question about to do something destructive: a red confirm button.
        case destructiveConfirmation
    }

    public let id: UUID
    public let title: String
    public let message: String
    public let style: Style
    /// Title of the button that goes through with it. `nil` for a notice that only reports.
    public let confirmTitle: String?
    public let onConfirm: (@MainActor () -> Void)?

    public init(
        title: String,
        message: String,
        style: Style = .error,
        confirmTitle: String? = nil,
        onConfirm: (@MainActor () -> Void)? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.style = style
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
    }

    /// True when the banner has to be answered rather than merely dismissed.
    public var isConfirmation: Bool { onConfirm != nil }
}

/// The one place that knows where the Settings window is.
@MainActor
public final class SettingsRouter: ObservableObject {
    public static let shared = SettingsRouter()

    /// What the detail column shows: the sidebar page, then pages drilled into from it. Never empty.
    @Published public private(set) var path: [SettingsPage] = [.general]

    /// Visited paths, oldest first, and the current index. Any non-history navigation drops forward entries.
    @Published public private(set) var history: [[SettingsPage]] = [[.general]]
    @Published public private(set) var historyIndex: Int = 0

    struct GeneralRevealRequest: Identifiable, Equatable {
        let id: UUID
        let targetID: String
    }
    @Published private(set) var generalRevealRequest: GeneralRevealRequest?

    @Published public var notice: SettingsNotice?

    /// Held here, not in the page: a `Binding` is not `Hashable`, and the edited page stays mounted under the chooser.
    public private(set) var iconTarget: Binding<String>?
    private var iconPickerToken = 0

    /// Configuration requests from outside the window (e.g. missing required options), read by the action's page.
    private var configurationRequests: [String: ConfigurationRequest] = [:]

    /// Toolbar menu picks, delivered to the page that owns the work; the window only forwards them.
    public let pageCommands = PassthroughSubject<String, Never>()

    static let historyLimit = 100
    static let transition: Animation = .easeInOut(duration: 0.22)

    public init() {}

    // MARK: - Where the window is

    public var sidebarPage: SettingsPage { path[0] }

    public var currentPage: SettingsPage { path[path.count - 1] }

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    // MARK: - Navigation

    /// Shows a sidebar page, dropping drilled-into pages. Instant: a cross-fade reads as lag.
    public func select(_ page: SettingsPage) {
        show(path: [page], animated: false)
    }

    func revealGeneralControl(_ targetID: String) {
        generalRevealRequest = GeneralRevealRequest(id: UUID(), targetID: targetID)
        select(.general)
    }

    func clearGeneralRevealRequest(_ id: UUID) {
        guard generalRevealRequest?.id == id else { return }
        generalRevealRequest = nil
    }

    /// Drills into a page from the current one; a page already in the path is returned to instead.
    public func push(_ page: SettingsPage) {
        if let index = path.firstIndex(of: page) {
            show(path: Array(path[...index]))
        } else {
            show(path: path + [page])
        }
    }

    /// Leaves the current page for the one it was reached from. A no-op on a sidebar page.
    public func pop() {
        guard path.count > 1 else { return }
        show(path: Array(path.dropLast()))
    }

    /// Returns to the sidebar page at the bottom of the path.
    public func popToRoot() {
        show(path: [sidebarPage])
    }

    /// Shows `newPath` and records it. Nothing happens when it is the current path already.
    public func show(path newPath: [SettingsPage], animated: Bool = true) {
        guard !newPath.isEmpty, newPath != path else { return }
        if animated {
            withAnimation(Self.transition) {
                path = newPath
            }
        } else {
            path = newPath
        }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(newPath)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
        historyIndex = history.count - 1
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        withAnimation(Self.transition) {
            path = history[historyIndex]
        }
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        withAnimation(Self.transition) {
            path = history[historyIndex]
        }
    }

    // MARK: - Icon chooser

    /// Drills into the icon chooser, which writes its pick to `binding`.
    public func pushIconPicker(writingTo binding: Binding<String>) {
        iconPickerToken += 1
        iconTarget = binding
        push(.iconPicker(token: iconPickerToken))
    }

    // MARK: - Configuration requests

    /// Opens an action's page for an outside request, keeping the request so the page can say what is missing.
    public func openConfiguration(for action: any Action, request: ConfigurationRequest?) {
        if let request, !action.chrome.launchesAI {
            configurationRequests[action.id] = request
        }
        show(path: SettingsDestination.path(for: action))
    }

    public func configurationRequest(for actionID: String) -> ConfigurationRequest? {
        configurationRequests[actionID]
    }

    public func clearConfigurationRequest(for actionID: String) {
        configurationRequests.removeValue(forKey: actionID)
    }

    // MARK: - Notices

    public func notify(_ notice: SettingsNotice) {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.notice = notice
        }
    }

    /// Reports a failure where an alert used to run modal over the window.
    public func notifyError(title: String, message: String) {
        notify(SettingsNotice(title: title, message: message, style: .error))
    }

    /// Asks before something destructive, where an alert used to. Escape and the banner's close
    /// button both mean "no"; only the red button goes through with it.
    public func confirmDestructive(
        title: String,
        message: String,
        confirmTitle: String,
        onConfirm: @escaping @MainActor () -> Void
    ) {
        notify(SettingsNotice(
            title: title,
            message: message,
            style: .destructiveConfirmation,
            confirmTitle: confirmTitle,
            onConfirm: onConfirm
        ))
    }

    /// Runs the current notice's confirmation and takes the banner down.
    public func confirmNotice() {
        let action = notice?.onConfirm
        dismissNotice()
        action?()
    }

    public func dismissNotice() {
        withAnimation(.easeInOut(duration: 0.2)) {
            notice = nil
        }
    }
}
