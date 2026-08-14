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

    /// Dedicated concurrent queue for blocking AX work (the inspect snapshot and the Edit ▸ Copy
    /// AXPress). Concurrent so a blocked accessibility call cannot prevent later inspectWithWatchdog
    /// and pressEditCopyMenu work from starting. AX lookups must never run on the cooperative thread
    /// pool: a hung call would pin one of those threads. Mirrors `PasteAvailabilityProbe.axProbeQueue`.
    private static let axInspectQueue = DispatchQueue(label: "com.openclip.ax-inspect", qos: .userInitiated, attributes: .concurrent)

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
    /// context or no strategy produced text. `cursor` is the system cursor class (`CursorClassifier.current`,
    /// which is `@MainActor`) captured by the caller; `.unknown` (unrecognized cursor) never blocks.
    /// `isSelectAll` marks a ⌘A gesture: a copy-based read is then skipped unless the focused element
    /// is text-bearing, so row selections in Finder/Mail/table views never fire a real copy.
    public func retrieve(
        for app: AppIdentity,
        policy: AppPolicyContext,
        cursor: CursorClass,
        isSelectAll: Bool = false
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

        // ⌘A select-all on a non-text element (row selection in Finder/Mail/table views) must never
        // produce text: AX reads would surface the row labels, and a copy trigger would fire a real
        // copy on rows, not text. Guard before the cascade so every strategy, not just copy modes,
        // honors it.
        if isSelectAll, !Self.isTextBearing(target) {
            Log.selection.debug("coordinator: select-all on non-text element; skipping retrieval")
            return nil
        }

        Log.selection.debug("coordinator: gate passed for \(app.bundleIdentifier ?? "unknown", privacy: .public); retrieving via \(policy.retrievalMode.rawValue, privacy: .public)")

        return Self.nonBlank(await read(for: app, target: target, policy: policy))
    }

    /// Resolves an ordered cascade of strategies from the inspected target and the app, then returns
    /// the first non-blank result. Unlike a single fixed `retrievalMode`, a failed primary strategy
    /// falls through to a copy-based strategy, so the target app itself can produce the selection
    /// when Accessibility cannot read it (the SelectedTextKit auto model).
    private func read(
        for app: AppIdentity,
        target: AXElementInspector.Target,
        policy: AppPolicyContext
    ) async -> TextResult? {
        for strategy in strategyCascade(for: policy) {
            if let result = await run(strategy, app: app, target: target) {
                return result
            }
        }
        return nil
    }

    /// Canonical fallback order. A policy selects a *preferred* strategy; retrieval runs that
    /// strategy followed by everything below it in this chain, so a failed read always degrades to
    /// a copy-based read. `browserScript` sits above `axWebArea` so a browser's preferred JS read
    /// still falls back to the AX web-area read before any copy. An app with no rule uses
    /// `.axTextControl` (index 0) and thus the full chain — the "auto" behavior. A rule never
    /// reaches strategies above its preferred entry point.
    private static let retrievalChain: [RetrievalStrategy] = [
        .axTextControl,
        .browserScript,
        .axWebArea,
        .menuCopy,
        .keyboardCopy
    ]

    private static let browserBundleIDs: Set<String> = Set(
        DefaultAppRules.safariGroup
            + DefaultAppRules.chromiumGroup
            + DefaultAppRules.firefoxGroup
            + DefaultAppRules.arcGroup
    )

    /// Returns the suffix of the chain starting at `policy.retrievalMode`'s preferred strategy.
    private func strategyCascade(for policy: AppPolicyContext) -> [RetrievalStrategy] {
        let preferred = RetrievalStrategy(mode: policy.retrievalMode)
        guard let index = Self.retrievalChain.firstIndex(of: preferred) else {
            return Self.retrievalChain
        }
        return Array(Self.retrievalChain[index...])
    }

    private func run(
        _ strategy: RetrievalStrategy,
        app: AppIdentity,
        target: AXElementInspector.Target
    ) async -> TextResult? {
        switch strategy {
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
            // Only browsers can answer over the JS bridge; a non-browser would just burn an osascript
            // subprocess and a timeout before falling through.
            guard let bundleIdentifier = app.bundleIdentifier,
                  Self.browserBundleIDs.contains(bundleIdentifier) else { return nil }
            if let browserResult = await browserRead(bundleIdentifier),
               !browserResult.text.isEmpty {
                return TextResult(text: browserResult.text, bounds: target.bounds)
            }
            return nil

        case .menuCopy, .keyboardCopy:
            // The copy engine is the source of truth for whether a selection existed: it returns nil
            // when the clipboard changeCount never advances or the copied string is empty, so a copy
            // on an empty selection fails cleanly instead of being pre-gated by a (possibly stale)
            // AX selection read.
            let trigger: CopyTrigger
            switch strategy {
            case .menuCopy:
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

    /// A leaf strategy in the fallback cascade.
    private enum RetrievalStrategy: Equatable {
        case axTextControl
        case axWebArea
        case browserScript
        case menuCopy
        case keyboardCopy

        init(mode: SelectionRetrievalMode) {
            switch mode {
            case .axTextControl: self = .axTextControl
            case .axWebArea: self = .axWebArea
            case .browserScript: self = .browserScript
            case .menuCopy: self = .menuCopy
            case .keyboardCopy: self = .keyboardCopy
            }
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

    /// Drops results whose text is empty or whitespace-only, so a selection with no usable text
    /// never reaches delivery. Every mode's result flows through here.
    private static func nonBlank(_ result: TextResult?) -> TextResult? {
        guard let result else { return nil }
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return result
    }

    /// Whether the focused element can hold a *text* selection (as opposed to a row/table selection
    /// that ⌘A would expand). True for editable text roles, anything inside a web area, and any
    /// element that already exposes a text selection range.
    private static func isTextBearing(_ target: AXElementInspector.Target) -> Bool {
        if target.selectedTextRange != nil { return true }
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea"]
        if let role = target.role, textRoles.contains(role) { return true }
        if !target.containedInRoles.isDisjoint(with: textRoles) { return true }
        return target.webArea != nil
    }

    /// AXPress the Edit ▸ Copy menu item of `app`'s menu bar via the robust menu navigator.
    /// Best-effort: a failed lookup performs no press and the pasteboard capture times out.
    private static func pressEditCopyMenu(app: AXUIElement?) {
        AXMenuNavigator.press(.copy, in: app)
    }
}