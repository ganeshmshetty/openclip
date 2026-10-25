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
    public static let togglePopup = Self("togglePopup", initial: .init(.c, modifiers: [.command, .option]))
    public static let captureText = Self("captureText", initial: .init(.o, modifiers: [.command, .option]))
    static let cancelCaptureText = Self("cancelCaptureText", initial: .init(.escape))

    static func actionHotkey(_ actionID: String) -> Self {
        Self("actionHotkey.\(actionID)")
    }
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private var lastFallbackClipboard: (changeCount: Int, text: String)?
    private weak var popupController: PopupWindowController?
    private weak var captureTextController: CaptureTextController?
    public weak var selectionMonitor: (any SelectionMonitoring)?
    internal var retriever: SelectionRetrievalCoordinator?
    internal var frontmostPIDProvider: @MainActor @Sendable () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    private var cancellables = Set<AnyCancellable>()
    private var registeredHotkeyIDs: Set<String> = []
    private var popupTriggerTask: Task<Void, Never>?
    private var popupTriggerRequestID: UUID?
    
    /// Does not consult `isAppEnabled` ("Appear Automatically" only gates the automatic popup).
    /// Pause, app exclusions, and per-app `disabled` rules still apply.
    internal static func triggerAllowed(
        frontmost: NSRunningApplication?,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> Bool {
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return false
        }
        guard let frontmost else { return false }
        if let bundleID = frontmost.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
            return false
        }
        // Bundle-less transient helpers cannot be configured, so never trigger.
        let identity = AppIdentity(frontmost)
        guard identity.ruleIdentifier != nil else { return false }
        return !RuleEngine.shared.resolvePolicies(for: identity).disabled
    }

    public func setup(
        popupController: PopupWindowController,
        selectionMonitor: (any SelectionMonitoring)? = nil
    ) {
        setup(popupController: popupController, selectionMonitor: selectionMonitor, captureTextController: nil)
    }

    func setup(
        popupController: PopupWindowController,
        selectionMonitor: (any SelectionMonitoring)?,
        captureTextController: CaptureTextController?
    ) {
        self.popupController = popupController
        self.selectionMonitor = selectionMonitor
        self.captureTextController = captureTextController
        // ⌘1…⌘9 must be global hot keys, not panel key equivalents (see PaletteRowShortcuts).
        PaletteRowShortcuts.install { [weak popupController] row in
            popupController?.runPaletteRow(row) ?? false
        }

        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            MainActor.assumeIsolated {
                self?.handleTogglePopup()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .captureText) { [weak self] in
            MainActor.assumeIsolated { self?.captureTextController?.toggleCapture() }
        }
        KeyboardShortcuts.onKeyDown(for: .cancelCaptureText) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.captureTextController?.isCapturing == true else { return }
                self.captureTextController?.cancel()
            }
        }
        KeyboardShortcuts.disable(.cancelCaptureText)

        ActionCoordinator.shared.$actions
            .sink { [weak self] actions in
                self?.registerActionHotkeys(actions)
            }
            .store(in: &cancellables)
        registerActionHotkeys(ActionCoordinator.shared.actions)
    }

    func enableCaptureCancellation() { KeyboardShortcuts.enable(.cancelCaptureText) }
    func disableCaptureCancellation() { KeyboardShortcuts.disable(.cancelCaptureText) }

    public func handleTogglePopup(frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        // A second press cancels a selection read that has not presented yet.
        if popupTriggerRequestID != nil {
            popupTriggerTask?.cancel()
            popupTriggerTask = nil
            popupTriggerRequestID = nil
            return
        }
        guard KeyboardShortcuts.isEnabled else { return }
        // Visible popup: search mode and the instruction prompt toggle off; actions bar switches into search.
        if let popupController = self.popupController, popupController.isVisible {
            if popupController.modeStore.mode == .search || popupController.modeStore.mode == .instruction {
                popupController.toggleMode()
            } else {
                popupController.enterSearch()
            }
            return
        }

        let requestID = UUID()
        let requestedPID = frontmostApp?.processIdentifier
        popupTriggerRequestID = requestID
        popupTriggerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.popupTriggerRequestID == requestID {
                    self.popupTriggerRequestID = nil
                    self.popupTriggerTask = nil
                }
            }

            let trigger: (context: SelectionContext, canPaste: Bool?)?
            if let frontmostApp {
                trigger = await self.collectTrigger(
                    frontmostApp: frontmostApp,
                    allowsEmptyText: true,
                    requestID: requestID,
                    requestedPID: requestedPID
                )
            } else {
                trigger = self.resolveSynchronousTrigger(frontmostApp: nil)
            }
            guard !Task.isCancelled,
                  KeyboardShortcuts.isEnabled,
                  self.popupTriggerRequestID == requestID,
                  DefaultSettingsStore.shared.get(.pauseUntilTimestamp) <= Date().timeIntervalSince1970,
                  let trigger else { return }
            if let requestedPID, let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier, currentPID != requestedPID {
                return
            }
            if let frontmostApp, !Self.triggerAllowed(frontmost: frontmostApp) { return }
            self.showSearch(for: trigger)
        }
    }

    private func showSearch(for trigger: (context: SelectionContext, canPaste: Bool?)) {
        // Empty selection and clipboard with no standalone actions: toast instead of an empty palette.
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

    /// Synchronous ⌥⌘C path: monitored selection, then clipboard, then empty context (zero delay).
    /// A nil `frontmostApp` skips per-app gating; the global pause still applies.
    internal func resolveSynchronousTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> (context: SelectionContext, canPaste: Bool?)? {
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return nil
        }

        // A nil frontmost app (clipboard-manager handoff) skips per-app checks.
        let appIdentity: AppIdentity
        let policy: AppPolicyContext
        let canUseMonitoredSelection: Bool

        if let identity = frontmostApp.map(AppIdentity.init), identity.ruleIdentifier != nil {
            if let bundleID = identity.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) { return nil }
            let resolved = RuleEngine.shared.resolvePolicies(for: identity)
            if resolved.disabled { return nil }
            appIdentity = identity
            policy = resolved
            canUseMonitoredSelection = true
        } else {
            // No identifiable app: per-app rules cannot apply; only the global pause does.
            appIdentity = AppIdentity(bundleIdentifier: nil, localizedName: nil)
            policy = .default
            canUseMonitoredSelection = false
        }

        // 1. Fast path: reuse active monitored selection if fresh (requires a known app)
        if canUseMonitoredSelection,
           let monitored = selectionMonitor?.synchronousSelection(for: appIdentity) {
            let text = monitored.context.text
            if TextSanitizer.isSubstantial(text),
               text.utf8.count <= Constants.maxTextLength {
                let context = monitored.context.with(cursorPosition: NSEvent.mouseLocation)
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
                isClipboardFallback: isClipboardFallback,
                html: pasteboard.string(forType: .html),
                rtf: pasteboard.string(forType: .rtf),
                isEditable: false
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
            isClipboardFallback: false,
            isEditable: false
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

    internal func handleActionHotkey(_ actionID: String, settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        guard let popupController else { return }
        guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == actionID }),
              ActionIdentity.isBindable(action),
              !(action is GatedExtensionAction) else { return }

        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)
        guard !disabledIDs.contains(action.id) else { return }
        if let pkgID = ActionIdentity.extensionPackageID(of: action), disabledPackages.contains(pkgID) {
            return
        }
        if action.chrome.launchesAI, !AIServiceManager.shared.isAIEnabled {
            return
        }
        if ActionIdentity.isAIPreset(action) {
            guard AIServiceManager.shared.isAIEnabled,
                  AIServiceManager.shared.preset(forActionID: action.id)?.isEnabled == true else {
                return
            }
        }
        let groupDefs = ActionCoordinator.shared.actionGroupDefs
        if let parentGroup = groupDefs.first(where: { $0.memberActionIDs.contains(action.id) }),
           disabledIDs.contains(parentGroup.id) {
            return
        }
        if let parentExtensionGroup = ActionCoordinator.shared.actions.first(where: {
            $0.chrome.popupBehavior == .showSubActions && action.id != $0.id && action.id.hasPrefix($0.id + ".")
        }), disabledIDs.contains(parentExtensionGroup.id) {
            return
        }

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

    /// Shared retrieve path for ⌥⌘C and per-action hotkeys.
    internal private(set) var lastTriggerResponse: SelectionTriggerResponse?
    internal var onTriggerOutcome: ((SelectionTriggerResponse) -> Void)?

    internal func collectTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        allowsEmptyText: Bool = false, requestID: UUID? = nil, requestedPID: pid_t? = nil
    ) async -> (context: SelectionContext, canPaste: Bool?)? {
        let response = await collectTriggerResponse(frontmostApp: frontmostApp,
            allowsEmptyText: allowsEmptyText, requestID: requestID, requestedPID: requestedPID)
        guard let context = response.context else { return nil }
        return (context, response.canPaste)
    }

    internal func collectTriggerResponse(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        allowsEmptyText: Bool = false,
        requestID: UUID? = nil,
        requestedPID: pid_t? = nil
    ) async -> SelectionTriggerResponse {
        func finish(_ response: SelectionTriggerResponse) -> SelectionTriggerResponse {
            lastTriggerResponse = response
            onTriggerOutcome?(response)
            if let traceID = response.traceID, [.clipboardFallback, .targetChanged, .cancelled, .tooLarge].contains(response.status) {
                Log.selection.debug("[Trace#\(traceID, privacy: .public)] hotkey delivery outcome: \(response.status.rawValue, privacy: .public); readOutcome=\(response.retrievalStatus?.rawValue ?? "unknown", privacy: .public)")
            }
            return response
        }
        let generation = selectionMonitor?.selectionGeneration
        guard !Task.isCancelled,
              Self.triggerAllowed(frontmost: frontmostApp),
              let frontApp = frontmostApp else { return finish(.init(status: Task.isCancelled ? .cancelled : .policyBlocked)) }

        let requiredPID = requestedPID ?? frontApp.processIdentifier
        let isTriggerAuthorized: PasteboardCopyEngine.CopyAuthorization = { [weak self] in
            guard !Task.isCancelled,
                  Self.triggerAllowed(frontmost: frontApp) else { return false }
            if let requestID, self?.popupTriggerRequestID != requestID { return false }
            guard self?.frontmostPIDProvider() == requiredPID else { return false }
            guard self?.selectionMonitor?.selectionGeneration == generation else { return false }
            return true
        }

        var retrievalTraceID: UInt64?
        func denied() -> SelectionTriggerResponse {
            let status: SelectionReadStatus = Task.isCancelled || (requestID != nil && popupTriggerRequestID != requestID)
                ? .cancelled : (!Self.triggerAllowed(frontmost: frontApp) ? .policyBlocked : .targetChanged)
            return finish(.init(status: status, traceID: retrievalTraceID))
        }

        let appIdentity = AppIdentity(frontApp)
        // Fast path: reuse active monitored selection without blocking on AX tree walk
        if let monitored = await selectionMonitor?.currentSelection(for: appIdentity) {
            guard isTriggerAuthorized() else { return denied() }
            let text = monitored.context.text
            if TextSanitizer.isSubstantial(text),
               text.utf8.count <= Constants.maxTextLength {
                let context = monitored.context.with(cursorPosition: NSEvent.mouseLocation)
                return finish(.init(context: context, canPaste: monitored.canPaste,
                    status: context.isClipboardFallback ? .clipboardFallback : .selection))
            }
        }

        guard isTriggerAuthorized() else { return denied() }
        let policy = RuleEngine.shared.resolvePolicies(for: appIdentity)
        let probeTask = popupController?.preparePasteProbe(for: frontApp, policy: policy)

        var retrievedText = ""
        var selectionBounds: CGRect? = nil
        var selectionHTML: String?
        var selectionRTF: String?
        var selectionFlavors: [RichPasteboardFlavor] = []

        let copyCapture: SelectionRetrievalCoordinator.DetailedCopyCapture = { request in
            await PasteboardCopyEngine(authorizationFailure: {
                if Task.isCancelled { return .cancelled }
                return isTriggerAuthorized() ? nil : .targetChanged
            }, isCopyAuthorized: isTriggerAuthorized).captureResponse(trigger: request.trigger)
        }

        let coordinator = retriever ?? SelectionRetrievalCoordinator(detailedCopyCapture: copyCapture)
        let read = await coordinator.retrieveResponse(
            for: appIdentity,
            policy: policy,
            cursor: CursorClassifier.current.asCore,
            allowCopyFallback: true,
            requireCopyEvidence: false,
            trigger: .keyboardShortcut
        )
        retrievalTraceID = read.traceID
        if let result = read.result {
            retrievedText = result.text
            selectionBounds = result.bounds
            selectionHTML = result.html
            selectionRTF = result.rtf
            selectionFlavors = result.flavors
        }

        guard isTriggerAuthorized() else { return denied() }

        if read.status == .cancelled || read.status == .targetChanged || read.status == .policyBlocked || read.status == .busy {
            return finish(.init(status: read.status))
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
                selectionHTML = pasteboard.string(forType: .html)
                selectionRTF = pasteboard.string(forType: .rtf)
                selectionFlavors = []
            }
        }

        if Task.isCancelled { return denied() }
        guard retrievedText.utf8.count <= Constants.maxTextLength else {
            return finish(.init(status: .tooLarge, retrievalStatus: read.status, traceID: read.traceID))
        }
        if !TextSanitizer.isSubstantial(retrievedText) {
            guard allowsEmptyText else { return finish(.init(status: read.status, retrievalStatus: read.status, traceID: read.traceID)) }
            retrievedText = ""
            isClipboardFallback = false
            selectionHTML = nil
            selectionRTF = nil
            selectionFlavors = []
        }

        var context = SelectionContext(
            text: retrievedText,
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: selectionBounds,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: isClipboardFallback,
            html: selectionHTML,
            rtf: selectionRTF,
            flavors: selectionFlavors,
            selectionGeneration: generation,
            isEditable: isClipboardFallback ? false : read.isEditable,
            traceID: read.traceID
        )
        let canPaste = await probeTask?.value
        context = context.with(pasteTargetAvailable: canPaste)
        guard isTriggerAuthorized() else { return denied() }
        return finish(.init(context: context, canPaste: canPaste,
            status: isClipboardFallback ? .clipboardFallback : (retrievedText.isEmpty ? .noSelection : .selection),
            retrievalStatus: read.status, traceID: read.traceID))
    }
}
