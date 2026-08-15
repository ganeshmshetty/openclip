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
    case copy(String)
    case cut(String)
    case paste(String)
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

    /// Surface a transient status (success/error/info) as a banner or corner badge. Keeps the popup open.
    case showStatus(StatusFeedback)
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
    /// top-level result (decision 8): `.showStatus` keeps the popup up, and a `.sequence` dismisses
    /// only when non-empty and every item dismisses. Everything else (leaf effects,
    /// `.openConfiguration`) dismisses.
    public var dismissesPopup: Bool {
        switch self {
        case .showStatus:
            return false
        case .sequence(let items):
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        default:
            return true // includes openConfiguration: hide bar, then open Preferences
        }
    }
}

extension ActionResult: Equatable {
    /// Value equality for results. `.failure` compares by error description text — enough for
    /// `ActionDelivery`/`ActionDelivery.none` to be `Equatable` without baking error identity in.
    public static func == (lhs: ActionResult, rhs: ActionResult) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success), (.simulatePaste, .simulatePaste), (.none, .none):
            return true
        case (.openURL(let a), .openURL(let b)):
            return a == b
        case (.copy(let a), .copy(let b)), (.cut(let a), .cut(let b)),
             (.paste(let a), .paste(let b)), (.showServices(let a), .showServices(let b)),
             (.copyDefinition(let a), .copyDefinition(let b)):
            return a == b
        case (.shareService(let ai, let at), .shareService(let bi, let bt)):
            return ai == bi && at == bt
        case (.notify(let at, let ab), .notify(let bt, let bb)):
            return at == bt && ab == bb
        case (.showStatus(let a), .showStatus(let b)):
            return a == b
        case (.openConfiguration(let a), .openConfiguration(let b)):
            return a == b
        case (.sequence(let a), .sequence(let b)):
            return a == b
        case (.keyPress(let a), .keyPress(let b)):
            return a == b
        case (.runShortcut(let an, let ai), .runShortcut(let bn, let bi)):
            return an == bn && ai == bi
        case (.failure(let a), .failure(let b)):
            return (a as? LocalizedError)?.errorDescription ?? String(describing: a)
                == (b as? LocalizedError)?.errorDescription ?? String(describing: b)
        default:
            return false
        }
    }
}
