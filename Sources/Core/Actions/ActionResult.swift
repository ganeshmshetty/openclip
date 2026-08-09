// ActionResult.swift
// OpenClip
//
// Defines the value enum representing execution results and platform side-effects returned by actions.
// Specifies outcomes such as copy, cut, paste, URL opening, system service triggers, notification
// posting, presentation results (content canvas, status, configuration), and simple success/failure. Also
// carries the popup dismissal policy computed once on a top-level result (decision 8).
import Foundation

public indirect enum ActionResult: Sendable {
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case copy(String)
    case cut(String)
    case paste(String)
    case showServices(String)

    /// Post a macOS user notification (title/body) via `UNUserNotificationCenter`. Handled by the
    /// effect door so Core and the JS host stay testable; best-effort (skipped if not authorized).
    case notify(title: String, body: String)

    // MARK: - Presentation results (presenter-owned; the effect handler treats these as no-ops)

    /// Render a content canvas on the popup panel. Keeps the popup open.
    case showContent(PopupContent)
    /// Render an interactive component tree on the popup panel (spec §7). The optional header is the
    /// running action's chrome title/icon; nil falls back to the controller's current-action header.
    /// Keeps the popup open. (Legacy `.showContent(PopupContent)` is deleted in Task 21.)
    case showContentTree(CanvasComponent, CanvasHeader?)
    /// Mount a scripting canvas session (spec §5.2): the engine evaluates the mount request, arms
    /// the session, and the tree re-renders via `.dispatch`. Keeps the popup open.
    /// Transient dead case until Task 24: no producer emits `.showCanvas` before the JS canvas
    /// producer (Task 24). Declared now for ecosystem completeness (exhaustive switches + the
    /// Task 21 final shape enumerate it); the first producer arms it in Task 24.
    case showCanvas(CanvasMountRequest, CanvasHeader)
    /// Surface a transient status (success/error/info) as a banner or corner badge. Keeps the popup open.
    case showStatus(StatusFeedback)
    /// Hide the popup and ask the user to configure the named action (opens Preferences → EditActionSheet).
    case openConfiguration(ConfigurationRequest)

    // MARK: - Flow combinators

    /// Perform the inner result but never dismiss the popup as a result of it.
    case keepVisible(ActionResult)
    /// Perform multiple results in order; the popup hides only if every item dismisses it.
    case sequence([ActionResult])

    // MARK: - Keyboard execution (Phase 8; no execution here)

    /// Send a synthetic key press to the frontmost app.
    case keyPress(KeyPressSpec)
    /// Run a registered shortcut by name with optional input.
    case runShortcut(name: String, input: String?)

    case none
}

extension ActionResult {
    /// Whether the popup should hide after this top-level result is handled. Computed once on the
    /// top-level result (decision 8): `.showContent`/`.showStatus` keep the popup up, `.keepVisible`
    /// explicitly suppresses dismissal, and a `.sequence` dismisses only when non-empty and every
    /// item dismisses. Everything else (leaf effects, `.openConfiguration`) dismisses.
    public var dismissesPopup: Bool {
        switch self {
        case .keepVisible, .showContent, .showContentTree, .showCanvas, .showStatus:
            return false
        case .sequence(let items):
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        default:
            return true // includes openConfiguration: hide bar, then open Preferences
        }
    }

    /// The effect a handler should actually execute, unwrapping `.keepVisible` so a leaf that was
    /// wrapped for presentation still reaches the effect door when driven outside the tree-walk.
    public var effectForHandler: ActionResult? {
        if case .keepVisible(let inner) = self { return inner }
        return self
    }
}
