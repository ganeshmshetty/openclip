// HotkeyManager.swift
// OpenClip
//
// Manages global keyboard shortcuts using macOS event monitors and KeyboardShortcuts registrations.
import Foundation
import AppKit
import Combine
import KeyboardShortcuts
import Core

extension KeyboardShortcuts.Name {
    public static let togglePopup = Self("togglePopup", default: .init(.c, modifiers: [.command, .option]))
    /// Instant AI: a one-line prompt on the selection whose answer replaces it in place.
    public static let instantAI = Self("instantAI", default: .init(.i, modifiers: [.command, .option]))

    static func actionHotkey(_ actionID: String) -> Self {
        Self("actionHotkey.\(actionID)")
    }
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private var lastFallbackClipboard: (changeCount: Int, text: String)?
    private weak var popupController: PopupWindowController?
    public weak var selectionMonitor: (any SelectionMonitoring)?
    private var cancellables = Set<AnyCancellable>()
    private var registeredHotkeyIDs: Set<String> = []
    
    /// Gating for the ⌥⌘C trigger. Deliberately does **not** consult `SettingKey.isAppEnabled`:
    /// that setting is "Appear Automatically" (both in Preferences and the menu bar), so it owns
    /// the selection monitor's automatic popup, not the explicit shortcut — turning automatic
    /// appearance off is the global form of the per-app `hotkeyOnly` rule, which has always kept
    /// the hotkey alive. The real kill switches still apply here: Pause OpenClip
    /// (`pauseUntilTimestamp`), the app-exclusion list, and a per-app `disabled` rule.
    internal static func triggerAllowed(
        frontmost: NSRunningApplication?,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> Bool {
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return false
        }
        guard let frontmost,
              let bundleID = frontmost.bundleIdentifier else { return false }
        if AppFilter.isExcluded(bundleID: bundleID) {
            return false
        }
        let policy = RuleEngine.shared.resolvePolicies(for: bundleID)
        return !policy.disabled
    }

    public func setup(
        popupController: PopupWindowController,
        selectionMonitor: (any SelectionMonitoring)? = nil
    ) {
        self.popupController = popupController
        self.selectionMonitor = selectionMonitor
        // ⌘1…⌘9 pick a palette row. Parked until a palette opens — see PaletteRowShortcuts for why
        // they must be global hot keys rather than key equivalents on the panel.
        PaletteRowShortcuts.install { [weak popupController] row in
            popupController?.runPaletteRow(row) ?? false
        }

        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            MainActor.assumeIsolated {
                self?.handleTogglePopup()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .instantAI) { [weak self] in
            MainActor.assumeIsolated {
                self?.handleInstantAI()
            }
        }

        ActionCoordinator.shared.$actions
            .sink { [weak self] actions in
                self?.registerActionHotkeys(actions)
            }
            .store(in: &cancellables)
        registerActionHotkeys(ActionCoordinator.shared.actions)
    }

    /// Instant AI: opens the one-line prompt on the current selection. Reuses the on-screen
    /// session when the popup is already up (bar, palette or card); otherwise resolves the
    /// selection synchronously exactly like ⌥⌘C. Needs real text — there is nothing to replace
    /// otherwise, so an empty selection gets a toast rather than an empty prompt.
    public func handleInstantAI() {
        if let popupController, popupController.isVisible, let context = popupController.currentContext {
            popupController.showInstantPrompt(for: context, pasteAvailable: popupController.modeStore.canPaste)
            return
        }
        guard let trigger = resolveSynchronousTrigger() else { return }
        guard Self.instantPromptAllowed(text: trigger.context.text) else {
            popupController?.showToast(
                StatusFeedback(message: String(localized: "Select some text first"), style: .info, symbolName: "text.cursor"),
                at: NSEvent.mouseLocation
            )
            return
        }
        popupController?.showInstantPrompt(for: trigger.context, pasteAvailable: trigger.canPaste)
    }

    /// Whether a selection is worth opening the Instant AI prompt for: substantial text only
    /// (the same bar as the automatic popup), since the answer is meant to replace it.
    static func instantPromptAllowed(text: String) -> Bool {
        TextSanitizer.isSubstantial(text) && text.utf8.count <= Constants.maxTextLength
    }

    public func handleTogglePopup() {
        // Popup already visible: if in search mode, the hotkey dismisses the popup (toggle off);
        // if in actions bar mode, the hotkey transitions directly into search mode.
        if let popupController = self.popupController, popupController.isVisible {
            if popupController.modeStore.mode == .search {
                popupController.toggleMode()
            } else {
                popupController.enterSearch()
            }
            return
        }

        guard let trigger = self.resolveSynchronousTrigger() else { return }

        // When both the monitored selection and clipboard are empty, check whether there are any
        // standalone actions (e.g. extensions declaring `requiresSelection: false`) available to run.
        // If not, avoid showing an empty search palette ("No matching actions" dead end); instead,
        // surface a lightweight floating toast anchored at the mouse cursor.
        if trigger.context.text.isEmpty {
            let actionContext = ActionContext(selection: trigger.context, modifiers: [])
            let catalog = ActionCoordinator.shared.searchCatalog(for: actionContext)
            let hasStandaloneActions = catalog.contains { $0.id != "builtin.paste" }
            if !hasStandaloneActions {
                popupController?.showToast(
                    StatusFeedback(
                        message: String(localized: "No text selected or on clipboard"),
                        style: .info,
                        symbolName: "doc.on.clipboard"
                    ),
                    at: NSEvent.mouseLocation
                )
                return
            }
        }

        self.popupController?.show(for: trigger.context, pasteAvailable: trigger.canPaste, initialMode: .search)
    }

    /// Synchronous retrieve path for ⌥⌘C: checks gating, reuses monitored selection,
    /// falls back to clipboard (paste fallback), or falls back to an empty context so the search
    /// palette opens with zero delay.
    ///
    /// When `frontmostApp` is `nil` (common during clipboard-manager handoffs) the method skips
    /// the per-app gating and monitored-selection paths, falling straight through to clipboard /
    /// empty-context. The global pause check still applies.
    internal func resolveSynchronousTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> (context: SelectionContext, canPaste: Bool?)? {
        // Global pause applies regardless of which app is frontmost.
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return nil
        }

        // When an identifiable frontmost app exists, apply per-app gating.
        // When it is nil (e.g. during a clipboard-manager → destination app transition)
        // skip the per-app checks and fall through to the clipboard / empty-context path.
        let appIdentity: AppIdentity
        let policy: AppPolicyContext
        let canUseMonitoredSelection: Bool

        if let frontApp = frontmostApp,
           let bundleID = frontApp.bundleIdentifier {
            if AppFilter.isExcluded(bundleID: bundleID) { return nil }
            let resolved = RuleEngine.shared.resolvePolicies(for: bundleID)
            if resolved.disabled { return nil }
            appIdentity = AppIdentity(frontApp)
            policy = resolved
            canUseMonitoredSelection = true
        } else {
            // No identifiable app — use a neutral identity. Per-app exclusion and disabled
            // rules cannot apply without a bundle ID, so we only honour the global pause
            // (checked above).
            appIdentity = AppIdentity(bundleIdentifier: nil, localizedName: nil)
            policy = .default
            canUseMonitoredSelection = false
        }

        // 1. Fast path: reuse active monitored selection if fresh (requires a known app)
        if canUseMonitoredSelection,
           let monitored = selectionMonitor?.synchronousSelection(for: frontmostApp?.bundleIdentifier) {
            let text = monitored.context.text
            if TextSanitizer.isSubstantial(text),
               text.utf8.count <= Constants.maxTextLength {
                let context = SelectionContext(
                    text: text,
                    sourceApp: monitored.context.sourceApp,
                    cursorPosition: NSEvent.mouseLocation,
                    mouseDownLocation: monitored.context.mouseDownLocation,
                    selectionBounds: monitored.context.selectionBounds,
                    timestamp: monitored.context.timestamp,
                    appPolicy: monitored.context.appPolicy,
                    isClipboardFallback: monitored.context.isClipboardFallback,
                    html: monitored.context.html,
                    rtf: monitored.context.rtf
                )
                return (context, monitored.canPaste)
            }
        }

        // 2. Paste fallback: read clipboard text synchronously
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        var retrievedText = ""
        var isClipboardFallback = false
        if let clipboard = pasteboard.string(forType: .string),
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            retrievedText = clipboard
            isClipboardFallback = true
            lastFallbackClipboard = (currentChangeCount, clipboard)
        }

        if TextSanitizer.isSubstantial(retrievedText),
           retrievedText.utf8.count <= Constants.maxTextLength {
            let context = SelectionContext(
                text: retrievedText,
                sourceApp: appIdentity,
                cursorPosition: NSEvent.mouseLocation,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: policy,
                isClipboardFallback: isClipboardFallback
            )
            return (context, nil)
        }

        // 3. Fallback to empty context so search palette still opens for standalone actions
        let emptyContext = SelectionContext(
            text: "",
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: false
        )
        return (emptyContext, nil)
    }

    private func registerActionHotkeys(_ actions: [any Action]) {
        for action in actions where ActionIdentity.isBindable(action) {
            let actionID = action.id
            guard registeredHotkeyIDs.insert(actionID).inserted else { continue }
            KeyboardShortcuts.onKeyUp(for: .actionHotkey(actionID)) { [weak self] in
                Task { @MainActor in
                    self?.handleActionHotkey(actionID)
                }
            }
        }
    }

    private func handleActionHotkey(_ actionID: String) {
        guard let popupController else { return }
        guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == actionID }),
              ActionIdentity.isBindable(action),
              !(action is GatedExtensionAction) else { return }

        if popupController.isVisible, let context = popupController.currentActionContext {
            popupController.runBoundAction(action, with: context)
            return
        }

        Task { @MainActor in
            guard let trigger = await self.collectTrigger() else { return }
            let context = ActionContext(selection: trigger.context, modifiers: [])
            popupController.runBoundAction(action, with: context, pasteAvailable: trigger.canPaste)
        }
    }

    /// Shared retrieve path for ⌥⌘C and per-action hotkeys: gate, probe paste, read selection
    /// (clipboard fallback), reject empty/oversized input.
    internal func collectTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) async -> (context: SelectionContext, canPaste: Bool?)? {
        guard Self.triggerAllowed(frontmost: frontmostApp),
              let frontApp = frontmostApp else { return nil }

        // Fast path: reuse active monitored selection without blocking on AX tree walk
        if let monitored = await selectionMonitor?.currentSelection(for: frontApp.bundleIdentifier) {
            let text = monitored.context.text
            if TextSanitizer.isSubstantial(text),
               text.utf8.count <= Constants.maxTextLength {
                let context = SelectionContext(
                    text: text,
                    sourceApp: monitored.context.sourceApp,
                    cursorPosition: NSEvent.mouseLocation,
                    mouseDownLocation: monitored.context.mouseDownLocation,
                    selectionBounds: monitored.context.selectionBounds,
                    timestamp: monitored.context.timestamp,
                    appPolicy: monitored.context.appPolicy,
                    isClipboardFallback: monitored.context.isClipboardFallback,
                    html: monitored.context.html,
                    rtf: monitored.context.rtf
                )
                return (context, monitored.canPaste)
            }
        }

        let policy = RuleEngine.shared.resolvePolicies(for: frontApp.bundleIdentifier ?? "")
        let appIdentity = AppIdentity(frontApp)
        let probeTask = popupController?.preparePasteProbe(for: frontApp, policy: policy)

        var retrievedText = ""
        var selectionBounds: CGRect? = nil

        if let result = await SelectionRetrievalCoordinator().retrieve(
            for: appIdentity,
            policy: policy,
            cursor: CursorClassifier.current
        ) {
            retrievedText = result.text
            selectionBounds = result.bounds
        }

        var isClipboardFallback = false
        if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pasteboard = NSPasteboard.general
            let currentChangeCount = pasteboard.changeCount
            if let clipboard = pasteboard.string(forType: .string),
               !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                retrievedText = clipboard
                isClipboardFallback = true
                lastFallbackClipboard = (currentChangeCount, clipboard)
            }
        }

        guard TextSanitizer.isSubstantial(retrievedText),
              retrievedText.utf8.count <= Constants.maxTextLength else { return nil }

        let context = SelectionContext(
            text: retrievedText,
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: selectionBounds,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: isClipboardFallback
        )
        let canPaste = await probeTask?.value
        return (context, canPaste)
    }
}
