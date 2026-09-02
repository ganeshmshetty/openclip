// ActionResult.swift
// OpenClip
//
// Defines the value enum representing execution results and platform side-effects returned by actions.
// Specifies outcomes such as copy, cut, paste, URL opening, system service triggers, notification
// posting, presentation results (status, configuration), and simple success/failure. Also
// carries the popup dismissal policy computed once on a top-level result (decision 8).
import Foundation

public indirect enum ActionResult: Sendable {
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case openURLInApp(url: URL, appBundleIdentifier: String)
    case copy(String)
    case cut(String)
    case paste(String)
    /// Rich multi-type paste (plain text, RTF, HTML).
    case pasteContent(RichPasteboardPayload)
    /// Rich multi-type copy (plain text, RTF, HTML).
    case copyContent(RichPasteboardPayload)
    /// Implicitly returned text — a JS string return, AppleScript output, shell plain-text stdout,
    /// or a text snippet. Unlike `.paste`, it carries no delivery decision: the user's per-click
    /// preference (General tab → "When an action returns text") decides preview / paste / copy in
    /// `ActionResultDelivery.resolve`. Explicit effects (openclip.paste/copy, JSON effects, declared
    /// `secondary`) are never re-decided. Does not auto-dismiss the popup; the controller decides
    /// dismissal from the resolved outcome.
    case text(String)
    case showServices(String)

    /// Look up `word` in the system dictionaries headlessly (no app launch) and copy its definition
    /// to the pasteboard. Declared by Core; resolved by the effect door via DictionaryServices so
    /// Core and the JS host stay testable. Returned by `DefineAction` on a force-copy click (the
    /// right-click/⇧-click alternative to opening Dictionary.app).
    case copyDefinition(String)

    /// Invoke a specific macOS sharing service by its identifier (e.g.
    /// `com.apple.Notes.SharingExtension`) with the given text — the sharing-extension analogue of
    /// `popclip.share(...)`. Handled by the effect door via `NSSharingService(named:).perform`,
    /// so Core and the JS host stay testable. Unlike `.showServices` (a picker), this targets the
    /// service directly (e.g. opens the Notes inline popup) and dismisses the popup.
    case shareService(identifier: String, text: String)

    /// Post a macOS user notification (title/body) via `UNUserNotificationCenter`. Handled by the
    /// effect door so Core and the JS host stay testable; best-effort (skipped if not authorized).
    case notify(title: String, body: String)

    // MARK: - Presentation results (presenter-owned; the effect handler treats these as no-ops)

    /// Surface a transient toast (success/error/info) as a banner or corner badge. Dismisses the
    /// popup by default; `keepVisible` opts out.
    case toast(StatusFeedback)
    /// Hide the popup and ask the user to configure the named action (opens Preferences → EditActionSheet).
    case openConfiguration(ConfigurationRequest)

    // MARK: - Flow combinators

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
    /// top-level result (decision 8): a `.toast` dismisses the popup by default (`keepVisible` opts
    /// out), and a `.sequence` dismisses only when non-empty and every item dismisses. Everything
    /// else (leaf effects, `.openConfiguration`) dismisses.
    public var dismissesPopup: Bool {
        switch self {
        case .toast(let feedback):
            return !feedback.keepVisible
        case .text:
            // Implicit returned text is a presentation result: dismissal is decided by the
            // controller from the resolved outcome (preview keeps the popup open; paste/copy dismiss).
            return false
        case .sequence(let items):
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        default:
            return true // includes openConfiguration: hide bar, then open Preferences
        }
    }

    /// True when this result (or any item of a `.sequence`) is a `.toast` — the presenter uses this
    /// to suppress the delivery companion toast so a script toast wins (one toast per run).
    public var containsToast: Bool {
        switch self {
        case .toast: return true
        case .text: return false
        case .sequence(let items): return items.contains(where: \.containsToast)
        default: return false
        }
    }
}
