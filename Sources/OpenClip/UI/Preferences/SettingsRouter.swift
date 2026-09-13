// SettingsRouter.swift
// OpenClip
//
// One object owns what the Settings window shows: a path of pages (the sidebar's selection first,
// any drilled-into pages after it) and the history of paths visited, so the toolbar's back and
// forward arrows work the way System Settings' do.
//
// Everything that used to float — the `.applicationDefined` popover on an action row, the icon
// picker popover on top of it, the sheet on top of that — is a page in this path now. Depth is a
// route, and the only way in or out is a navigation that the window's chrome can see and undo.
//
// A shared object rather than view state because the rows that navigate are hosted in an
// `NSOutlineView`, which rebuilds its cell views on every model change: a row cannot own the
// route it points at.

import SwiftUI
import Combine
import Core

/// Everything the Settings window can show.
///
/// The first group are sidebar rows. The second are pages reached from a sidebar page and shown in
/// the same column with the toolbar's back arrow as the way out.
public enum SettingsPage: Hashable, Identifiable, Sendable {
    // Sidebar — OpenClip
    case general
    case appearance
    /// The popup bar's layout: the order of everything on it, and custom groups. Nothing else —
    /// every action's own settings live on the action's page.
    case customize
    case shortcuts
    case appRules
    case store
    case about

    // Sidebar — the second group. AI first, then every built-in action, every installed
    /// extension and the user's custom actions, one row each, by name.
    case ai
    case extensionPackage(id: String)
    /// A built-in action's settings (Copy, Search, Calculate, …), as its own sidebar row.
    case builtinAction(id: String)
    /// The user's own Open URL / Text Snippet / Shell Script actions.
    case customActions

    // Pages reached from a sidebar page.
    /// One action's settings, or one group's when the id names a group.
    case action(id: String)
    case newCustomAction
    case newGroup(memberIDs: [String])
    /// The icon chooser. It writes to the binding held in `SettingsRouter.iconTarget`; the token
    /// only keeps two consecutive choosers distinct in the path.
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
        case .newCustomAction: return "newCustomAction"
        case .newGroup: return "newGroup"
        case .iconPicker(let token): return "iconPicker:\(token)"
        case .aiPreset(let id): return "aiPreset:\(id)"
        case .aiNewPreset: return "aiNewPreset"
        case .addApplication: return "addApplication"
        }
    }

    /// The sidebar's first group, in order.
    public static let systemPages: [SettingsPage] = [
        .general, .appearance, .customize, .appRules, .store, .about
    ]

    /// True for pages the sidebar lists; false for pages reached from one of them.
    public var isSidebarPage: Bool {
        switch self {
        case .general, .appearance, .customize, .shortcuts, .appRules, .store, .about, .ai, .extensionPackage,
             .builtinAction, .customActions:
            return true
        case .action, .newCustomAction, .newGroup, .iconPicker, .aiPreset, .aiNewPreset, .addApplication:
            return false
        }
    }

    /// The title for pages whose title does not depend on data. An action's page is titled after
    /// the action, an extension's after the extension; those are resolved by the window.
    public var staticTitle: String? {
        switch self {
        case .general: return String(localized: "General")
        case .appearance: return String(localized: "Appearance")
        case .customize: return String(localized: "Customize")
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

    /// Sidebar glyph for the system pages.
    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .customize: return "slider.horizontal.3"
        case .shortcuts: return "command"
        case .appRules: return "shield.checkered"
        case .store: return "bag.fill"
        case .about: return "info.circle.fill"
        case .ai: return "sparkles"
        case .extensionPackage: return "puzzlepiece.extension.fill"
        case .builtinAction: return "bolt.fill"
        case .customActions: return "wand.and.stars"
        case .action: return "slider.horizontal.3"
        case .newCustomAction: return "plus.circle.fill"
        case .newGroup: return "folder.fill.badge.plus"
        case .iconPicker: return "photo.on.rectangle"
        case .aiPreset, .aiNewPreset: return "text.bubble.fill"
        case .addApplication: return "app.badge.checkmark"
        }
    }

    /// Sidebar tile colour. The app's own settings are grey so they recede; what OpenClip ships
    /// is the brand blue; a third-party extension's colour comes from its identifier. See
    /// `SettingsTint`.
    var tint: Color {
        switch self {
        case .general, .appearance, .customize, .shortcuts, .appRules, .store, .about:
            return SettingsTint.system
        case .ai, .customActions, .builtinAction:
            return SettingsTint.openClip
        case .extensionPackage(let id):
            return SettingsTint.extensionTint(for: id)
        case .action, .newCustomAction, .newGroup, .iconPicker, .aiPreset, .aiNewPreset, .addApplication:
            return SettingsTint.openClip
        }
    }

    /// Terms the sidebar search matches besides the title, so "hotkey" finds Shortcuts and
    /// "api key" finds AI. Extension rows add their own keywords from the manifest.
    var searchKeywords: [String] {
        switch self {
        case .general: return ["startup", "launch", "login", "menu bar", "trigger", "hotkey", "permission", "accessibility", "paste", "copy", "preview"]
        case .appearance: return ["theme", "dark", "light", "glass", "popup", "preview"]
        case .customize: return ["actions", "popup bar", "order", "reorder", "arrange", "group", "groups", "layout", "install", "shortcuts", "hotkey", "keyboard", "alias", "shortcut", "key", "binding"]
        case .shortcuts: return ["hotkey", "keyboard", "alias", "shortcut", "key", "binding"]
        case .appRules: return ["apps", "exclude", "allow", "block", "rules", "disable", "per-app"]
        case .store: return ["extensions", "install", "catalog", "browse", "download"]
        case .about: return ["version", "update", "licence", "license", "logs", "diagnostics", "github"]
        case .ai: return ["model", "api key", "prompt", "openai", "claude", "gemini", "ollama", "cli", "local", "cloud", "apple intelligence", "rewrite", "summarize"]
        case .customActions: return ["custom", "snippet", "script", "shell", "url", "open url", "text snippet", "my actions"]
        case .extensionPackage, .builtinAction, .action, .newCustomAction, .newGroup, .iconPicker, .aiPreset, .aiNewPreset, .addApplication:
            return []
        }
    }
}

/// An inline message the window shows instead of an alert: a failed removal, a failed export, or
/// the question an alert used to ask before something destructive ("Uninstall JWT?").
///
/// A confirmation carries the work it would do, so the page that asked keeps owning it — the
/// banner only draws the question and the button.
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

    /// What the detail column shows: the sidebar's page first, then every page drilled into from
    /// it. Never empty.
    @Published public private(set) var path: [SettingsPage] = [.general]

    /// Every path visited, oldest first, and where in it the window is. Back and forward move
    /// `historyIndex`; any other navigation drops the forward entries and appends, the way a web
    /// browser's history does.
    @Published public private(set) var history: [[SettingsPage]] = [[.general]]
    @Published public private(set) var historyIndex: Int = 0

    /// The notice the detail column is showing, if any.
    @Published public var notice: SettingsNotice?

    /// Where the icon chooser writes. Held here, outside the page, because a `Binding` is not
    /// `Hashable` and the page whose draft it edits stays mounted underneath the chooser.
    public private(set) var iconTarget: Binding<String>?
    private var iconPickerToken = 0

    /// Requests to configure an action that arrived from outside the window (the popup found an
    /// action with missing required options). The action's page reads and shows them.
    private var configurationRequests: [String: ConfigurationRequest] = [:]

    /// Picks from the toolbar's ellipsis menu, delivered to whichever page put them there. The
    /// page owns the work (a draft to reset, an editor to leave), so the window forwards rather
    /// than acting: see `SettingsToolbarCommand` for the ids.
    public let pageCommands = PassthroughSubject<String, Never>()

    static let historyLimit = 100
    static let transition: Animation = .easeInOut(duration: 0.22)

    public init() {}

    // MARK: - Where the window is

    /// The sidebar's selection.
    public var sidebarPage: SettingsPage { path[0] }

    /// The page on screen.
    public var currentPage: SettingsPage { path[path.count - 1] }

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    // MARK: - Navigation

    /// Shows a sidebar page, dropping whatever was drilled into from the previous one.
    public func select(_ page: SettingsPage) {
        show(path: [page])
    }

    /// Drills into `page` from the current one. Drilling into a page that is already in the path
    /// returns to it instead of stacking a second copy.
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
    public func show(path newPath: [SettingsPage]) {
        guard !newPath.isEmpty, newPath != path else { return }
        withAnimation(Self.transition) {
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

    /// Opens an action's page because something outside the window asked for it, keeping the
    /// request so the page can explain why and highlight what is missing.
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
