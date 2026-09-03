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

public struct SelectionRetrievalCoordinator: Sendable {
    public typealias TargetProvider = @Sendable () -> AXElementInspector.Target
    public typealias BrowserReader = @Sendable (String) async -> BrowserScriptStrategy.BrowserResult?
    public typealias CopyTrigger = PasteboardCopyEngine.CopyTrigger
    public typealias CopyCapture = @Sendable (CopyTrigger) async -> TextResult?

    /// Dedicated concurrent queue for blocking AX work (the inspect snapshot and the Edit ▸ Copy
    /// AXPress). Concurrent so a blocked accessibility call cannot prevent later inspectWithWatchdog
    /// and pressEditCopyMenu work from starting. AX lookups must never run on the cooperative thread
    /// pool: a hung call would pin one of those threads. Mirrors `PasteAvailabilityProbe.axProbeQueue`.
    private static let axInspectQueue = DispatchQueue(label: "com.openclip.ax-inspect", qos: .userInitiated, attributes: .concurrent)

    /// Bounds how many selection reads may be actively awaited at once (`Constants.axMaxConcurrentInspects`).
    /// Unlike the single fail-fast slot it replaces, overlapping gestures — quick re-selection,
    /// double-click, hotkey+monitor races — each get their own read, and a permit frees when the
    /// caller's watchdog deadline settles its continuation, NOT when a hung underlying AX call
    /// eventually returns. One slow app therefore cannot make every later popup miss.
    private actor InspectConcurrencyGate {
        private var inFlight = 0
        func tryAcquire(limit: Int) -> Bool {
            guard inFlight < limit else { return false }
            inFlight += 1
            return true
        }
        func release() {
            inFlight -= 1
        }
    }
    private static let inspectGate = InspectConcurrencyGate()

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
    static func defaultCopyCapture(_ trigger: CopyTrigger) async -> TextResult? {
        await PasteboardCopyEngine().capture(trigger: trigger)
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
        // Elements in web areas or containing web content frequently use role="button" or <button>
        // for clickable text/tags that are legitimately selectable.
        let isWeb = target.webArea != nil || target.role == "AXWebArea" || target.containedInRoles.contains("AXWebArea")
        if let role = target.role, policy.gate.skipRoles.contains(role) {
            if !(isWeb && role == "AXButton") {
                Log.selection.debug("coordinator: skipping \(app.bundleIdentifier ?? "unknown", privacy: .public); role \(role, privacy: .private) is gated")
                return nil
            }
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
        let bundleID = app.bundleIdentifier ?? "unknown"
        let strategies = strategyCascade(for: policy, target: target, bundleIdentifier: app.bundleIdentifier)

        for (index, strategy) in strategies.enumerated() {
            if index > 0 {
                let previous = strategies[index - 1]
                Log.selection.debug("coordinator: \(previous.rawValue, privacy: .public) produced no text for \(bundleID, privacy: .public); falling back to \(strategy.rawValue, privacy: .public)")
            }
            if let result = Self.nonBlank(await run(strategy, app: app, target: target)) {
                if index > 0 {
                    Log.selection.debug("coordinator: fallback \(strategy.rawValue, privacy: .public) succeeded for \(bundleID, privacy: .public)")
                } else {
                    Log.selection.debug("coordinator: primary \(strategy.rawValue, privacy: .public) succeeded for \(bundleID, privacy: .public)")
                }
                return await enrichRichContent(result, strategy: strategy, app: app, target: target)
            }
        }
        Log.selection.debug("coordinator: all strategies exhausted for \(bundleID, privacy: .public); no selection")
        return nil
    }

    /// A text-only win on web content silently lacks the page's rich markup (AX exposes only plain
    /// text), so HTML-consuming actions receive an empty representation. When the winning strategy
    /// cannot carry HTML/RTF and the context is a web area or known browser, re-read the selection
    /// through a real copy capture (archive → ⌘C → poll → restore): browsers write public.html /
    /// public.rtf for selections. The captured result replaces the AX read; a failed or still-plain
    /// capture returns the original untouched.
    private func enrichRichContent(
        _ result: TextResult,
        strategy: RetrievalStrategy,
        app: AppIdentity,
        target: AXElementInspector.Target
    ) async -> TextResult {
        guard result.html == nil && result.rtf == nil else { return result }
        guard strategy != .keyboardCopy && strategy != .menuCopy else { return result }
        let bundleIsBrowser = Self.isScriptableBrowser(app.bundleIdentifier)
        guard bundleIsBrowser || target.webArea != nil || target.role == "AXWebArea" else { return result }
        Log.selection.debug("coordinator: text-only web selection; enriching via pasteboard rich capture")
        guard let captured = Self.nonBlank(await run(.keyboardCopy, app: app, target: target)),
              captured.html != nil || captured.rtf != nil else {
            return result
        }
        return TextResult(
            text: captured.text,
            bounds: result.bounds ?? captured.bounds,
            html: captured.html,
            rtf: captured.rtf
        )
    }

    /// Bundle-id PATTERNS of scriptable browsers, matched with `DefaultAppRules` wildcard
    /// semantics. A raw Set lookup here silently missed every pattern entry (e.g.
    /// `com.google.Chrome.*`), so Chromium-family apps never reached the AppleScript read.
    private static let browserBundlePatterns: [String] = Array(Set(
        DefaultAppRules.safariGroup
            + DefaultAppRules.chromiumGroup
            + DefaultAppRules.firefoxGroup
            + DefaultAppRules.arcGroup
    ))

    private static func isScriptableBrowser(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return DefaultAppRules.matchesAny(browserBundlePatterns, bundleID: bundleIdentifier)
    }

    private static let strictlyNativeBundleIDs: Set<String> = Set(
        DefaultAppRules.nativeApps
    )

    /// Resolves targeted strategies for `policy.retrievalMode`, providing tiered fallback
    /// where dynamic web content requires it, while strictly confining native controls and terminals
    /// to their direct mechanisms to eliminate redundant double timeouts and false cascades.
    private func strategyCascade(
        for policy: AppPolicyContext,
        target: AXElementInspector.Target,
        bundleIdentifier: String?
    ) -> [RetrievalStrategy] {
        switch policy.retrievalMode {
        case .axTextControl:
            // Embedded webview (e.g. Apple Mail email body, Help viewer, Xcode documentation) -> web cascade
            if target.webArea != nil || target.role == "AXWebArea" || target.containedInRoles.contains("AXWebArea") {
                return [.axWebArea, .keyboardCopy]
            }
            // Preview.app viewing PDFs uses PDFView (AXScrollArea/AXPage) which doesn't expose AX text controls;
            // allow keyboard-copy fallback.
            if bundleIdentifier == "com.apple.Preview" {
                return [.axTextControl, .keyboardCopy]
            }
            // 100% native Apple apps (Notes, TextEdit, Pages, Finder, etc.) are strictly authoritative in AX.
            // When AX reports no text selected, terminate immediately in 0ms without redundant ⌘C copy.
            if let bundleIdentifier, Self.strictlyNativeBundleIDs.contains(bundleIdentifier) {
                return [.axTextControl]
            }
            // Unlisted third-party apps -> AX with keyboard-copy safety net
            return [.axTextControl, .keyboardCopy]

        case .axWebArea, .browserScript:
            return [.axWebArea, .keyboardCopy]

        case .menuCopy:
            return [.menuCopy]

        case .keyboardCopy:
            return [.keyboardCopy]
        }
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
            // Web-area text can lag the focus snapshot. Poll the element directly for the selection
            // to appear, falling back to fresh inspection if the element is unavailable.
            var snapshot: AXElementInspector.Target? = target
            var attempts = 0
            while attempts < Constants.webAreaSettleMaxRetries {
                if let snapshot, let result = AXWebAreaStrategy.read(from: snapshot) {
                    return result
                }
                attempts += 1
                if attempts < Constants.webAreaSettleMaxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(Constants.webAreaSettleInterval * 1_000_000_000))
                    if let element = snapshot?.webArea ?? snapshot?.focusedElement,
                       let result = AXWebAreaStrategy.pollFresh(from: element) {
                        return result
                    }
                    snapshot = await inspectWithWatchdog()
                }
            }
            return nil

        case .browserScript:
            return nil

        case .menuCopy, .keyboardCopy:
            // The copy engine is the source of truth for whether a selection existed: it returns nil
            // when the clipboard changeCount never advances or the copied string is empty, so a copy
            // on an empty selection fails cleanly instead of being pre-gated by a (possibly stale)
            // AX selection read.
            let trigger: CopyTrigger
            switch strategy {
            case .menuCopy:
                trigger = {
                    Task.detached {
                        // Serialize menu presses through the shared gate; a press skipped under
                        // saturation just lets the pasteboard capture time out to nil.
                        guard await Self.inspectGate.tryAcquire(limit: Constants.axMaxConcurrentInspects) else { return }
                        Self.axInspectQueue.async {
                            Self.pressEditCopyMenu(app: target.focusedApp)
                            Task.detached { await Self.inspectGate.release() }
                        }
                    }
                }
            case .keyboardCopy:
                trigger = { SessionEventTapPoster().postKey(keyCode: Constants.copyVirtualKey, flags: .maskCommand) }
            default:
                return nil
            }
            guard let captured = await copyCapture(trigger) else { return nil }
            return TextResult(text: captured.text, bounds: target.bounds, html: captured.html, rtf: captured.rtf)
        }
    }

    /// A leaf strategy in the fallback cascade.
    private enum RetrievalStrategy: String, Equatable, Sendable {
        case axTextControl = "ax-text-control"
        case axWebArea = "ax-web-area"
        case browserScript = "browser-script"
        case menuCopy = "menu-copy"
        case keyboardCopy = "keyboard-copy"

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
    /// Whichever side settles the continuation (worker or watchdog) also frees its concurrency
    /// permit, so the gate is never held past the caller's budget by a still-blocked worker.
    private func inspectWithWatchdog() async -> AXElementInspector.Target? {
        guard await Self.inspectGate.tryAcquire(limit: Constants.axMaxConcurrentInspects) else {
            Log.selection.debug("coordinator: inspect concurrency cap reached; skipping read")
            return nil
        }
        let inspect = self.inspect
        return await withCheckedContinuation { (continuation: CheckedContinuation<AXElementInspector.Target?, Never>) in
            let resume = OnceResume<AXElementInspector.Target?>()
            let timeout = TaskBox()

            timeout.set(Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.axReadTimeout * 1_000_000_000))
                if resume.resume(continuation, with: nil) {
                    Task.detached { await Self.inspectGate.release() }
                    Log.selection.debug("coordinator: AX inspect exceeded \(Constants.axReadTimeout)s deadline; returning nil")
                }
            })

            Self.axInspectQueue.async {
                let target = inspect()
                if resume.resume(continuation, with: target) {
                    timeout.cancel()
                    Task.detached { await Self.inspectGate.release() }
                }
            }
        }
    }

    // MARK: - AX Edit ▸ Copy press (menu-copy mode)

    /// Drops results whose text is empty, whitespace-only, or non-printable, so a selection with no usable text
    /// never reaches delivery. Every mode's result flows through here.
    private static func nonBlank(_ result: TextResult?) -> TextResult? {
        guard let result else { return nil }
        guard TextSanitizer.isSubstantial(result.text) else { return nil }
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