// SelectionRetrievalCoordinator.swift
// OpenClip
//
// Routes a selection-retrieval request through the gate (skip-roles / cursor class), resolves the
// app's retrieval mode, and delegates to the matching strategy. The blocking AX snapshot
// (AXElementInspector.inspect) runs off the cooperative pool on a dedicated queue, raced against
// Constants.axReadTimeout so a slow or unresponsive target app can never hang the popup.
import ApplicationServices
import CoreGraphics
import Foundation
import Core

public struct SelectionRetrievalCoordinator {
    public typealias TargetProvider = @Sendable () -> AXElementInspector.Target
    public typealias BrowserReader = @Sendable (String) async -> BrowserScriptStrategy.BrowserResult?
    public typealias CopyTrigger = PasteboardCopyEngine.CopyTrigger
    public typealias CopyCapture = @Sendable (CopyTrigger) async -> String?

    /// Dedicated serial queue for blocking AX work (the inspect snapshot and the Edit ▸ Copy AXPress).
    /// AX lookups must never run on the cooperative thread pool: a hung call would pin one of those
    /// threads. Mirrors `PasteAvailabilityProbe.axProbeQueue`.
    private static let axInspectQueue = DispatchQueue(label: "com.openclip.ax-inspect", qos: .userInitiated)

    private let inspect: TargetProvider
    private let browserRead: BrowserReader
    private let copyCapture: CopyCapture

    /// The strategies are injectable so unit tests can exercise the gate and mode routing with
    /// fixture targets instead of the live accessibility tree (production defaults run live AX).
    public init(
        inspect: @escaping TargetProvider = { AXElementInspector.inspect() },
        browserRead: @escaping BrowserReader = { bundleIdentifier in
            await BrowserScriptStrategy.read(bundleIdentifier: bundleIdentifier)
        },
        copyCapture: @escaping CopyCapture = Self.defaultCopyCapture
    ) {
        self.inspect = inspect
        self.browserRead = browserRead
        self.copyCapture = copyCapture
    }

    /// The production copy capture: archive the pasteboard, run the copy trigger, poll for the
    /// change, and restore. A `@MainActor` call (PasteboardCopyEngine is main-actor-isolated), so it
    /// is referenced from the default argument via this static instead of a default-arg closure.
    @usableFromInline
    static func defaultCopyCapture(_ trigger: CopyTrigger) async -> String? {
        await PasteboardCopyEngine().captureString(trigger: trigger)
    }

    /// Reads the current selection for `app` under `policy`, or `nil` when the gate rejects the
    /// context or no strategy produced text. `cursor` defaults to the live system cursor class;
    /// `.unknown` (unrecognized cursor) never blocks.
    public func retrieve(
        for app: AppIdentity,
        policy: AppPolicyContext,
        cursor: CursorClass = CursorClassifier.current
    ) async -> TextResult? {
        let target = await inspectWithWatchdog()
        guard let target else {
            Log.selection.debug("coordinator: AX inspect timed out for \(app.bundleIdentifier ?? "unknown", privacy: .public); no selection")
            return nil
        }

        // Gate 1: skip UI roles that can never hold a text selection.
        if let role = target.role, policy.gate.skipRoles.contains(role) {
            Log.selection.debug("coordinator: skipping \(app.bundleIdentifier ?? "unknown", privacy: .public); role \(role, privacy: .private) is gated")
            return nil
        }

        // Gate 2: only read when the cursor class suggests a text context. `.unknown` is never a
        // reason to block (the classifier may simply not recognize the cursor image).
        if cursor != .unknown, !policy.gate.allowedCursors.contains(cursor) {
            Log.selection.debug("coordinator: skipping \(app.bundleIdentifier ?? "unknown", privacy: .public); cursor \(cursor.rawValue, privacy: .public) not allowed")
            return nil
        }

        switch policy.retrievalMode {
        case .axTextControl:
            return AXTextControlStrategy.read(from: target)

        case .axWebArea:
            // Web-area text can lag the focus snapshot, and the snapshot itself can go stale while
            // the page settles. Re-inspect fresh on every retry (Global Constraint: resolve fresh
            // on every call) so the loop actually observes the text appearing instead of re-reading
            // a frozen target; return on the first settled read.
            var snapshot: AXElementInspector.Target? = target
            var attempts = 0
            while attempts < Constants.webAreaSettleMaxRetries {
                if let snapshot, let result = AXWebAreaStrategy.read(from: snapshot) {
                    return result
                }
                attempts += 1
                if attempts < Constants.webAreaSettleMaxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(Constants.webAreaSettleInterval * 1_000_000_000))
                    snapshot = await inspectWithWatchdog()
                }
            }
            return nil

        case .browserScript:
            if let bundleIdentifier = app.bundleIdentifier,
               let browserResult = await browserRead(bundleIdentifier),
               !browserResult.text.isEmpty {
                return TextResult(text: browserResult.text, bounds: target.bounds)
            }
            return AXWebAreaStrategy.read(from: target)

        case .menuCopy, .keyboardCopy:
            let hasConfirmedSelection = await MainActor.run { PasteboardCopyEngine.hasSelection(target.selectedText) }
            guard hasConfirmedSelection || !policy.gate.requireSelectionBeforeCopy else {
                Log.selection.debug("coordinator: \(policy.retrievalMode.rawValue, privacy: .public) blocked; no confirmed selection and selection is required")
                return nil
            }
            let trigger: CopyTrigger
            switch policy.retrievalMode {
            case .menuCopy:
                // AXPress Edit ▸ Copy off the cooperative pool while the pasteboard engine polls.
                trigger = { Self.axInspectQueue.async { Self.pressEditCopyMenu(app: target.focusedApp) } }
            case .keyboardCopy:
                trigger = { SessionEventTapPoster().postKey(keyCode: Constants.copyVirtualKey, flags: .maskCommand) }
            default:
                return nil
            }
            guard let text = await copyCapture(trigger) else { return nil }
            return TextResult(text: text, bounds: target.bounds)
        }
    }

    /// Runs the blocking AX snapshot off the cooperative pool, racing it against
    /// `Constants.axReadTimeout` so a hung target app yields `nil` instead of stalling the popup.
    private func inspectWithWatchdog() async -> AXElementInspector.Target? {
        let inspect = self.inspect
        return await withCheckedContinuation { (continuation: CheckedContinuation<AXElementInspector.Target?, Never>) in
            let resume = OnceResume<AXElementInspector.Target?>()
            let timeout = TaskBox()

            timeout.set(Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.axReadTimeout * 1_000_000_000))
                if resume.resume(continuation, with: nil) {
                    Log.selection.debug("coordinator: AX inspect exceeded \(Constants.axReadTimeout)s deadline; returning nil")
                }
            })

            Self.axInspectQueue.async {
                let target = inspect()
                if resume.resume(continuation, with: target) {
                    timeout.cancel()
                }
            }
        }
    }

    // MARK: - AX Edit ▸ Copy press (menu-copy mode)

    /// AXPress the Edit ▸ Copy menu item of `app`'s menu bar. Localization-agnostic title matching
    /// (an "Edit" top-level menu containing a "Copy" item), mirroring the retired
    /// `MacTextRetriever.strategyAXMenuCopy` walk. Best-effort: a failed lookup performs no press and
    /// the pasteboard capture times out.
    private static func pressEditCopyMenu(app: AXUIElement?) {
        guard let app else { return }
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef, CFGetTypeID(menuBarRef) == AXUIElementGetTypeID(),
              let children = copyChildren(menuBarRef as! AXUIElement) else { return }

        for item in children {
            guard let title = copyTitle(item), title.localizedCaseInsensitiveContains("Edit") else { continue }
            let menuChildren = copyChildren(item) ?? []
            let menu = menuChildren.first ?? item
            guard let menuItems = copyChildren(menu) else { return }
            for copyCandidate in menuItems {
                guard let copyTitle = copyTitle(copyCandidate), copyTitle.localizedCaseInsensitiveContains("Copy") else { continue }
                AXUIElementPerformAction(copyCandidate, kAXPressAction as CFString)
                return
            }
        }
    }

    private static func copyTitle(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else { return nil }
        return ref as? [AXUIElement]
    }
}