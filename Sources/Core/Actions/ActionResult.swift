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

    /// Show the system Look Up dictionary popover for `word`. Declared by Core; presented by the
    /// effect door via `NSView.showDefinition(for:at:)` so Core stays AppKit-free. Pure presentation —
    /// nothing is written to the pasteboard and the popup stays open so the popover keeps its anchor.
    case showDefinition(String)

    /// Look up `word` in the system dictionaries headlessly (no app launch) and copy its definition
    /// to the pasteboard. Declared by Core; resolved by the effect door via DictionaryServices so
    /// Core and the JS host stay testable. Returned by `DefineAction` on a force-copy click (the
    /// right-click/⇧-click alternative to opening Dictionary.app).
    case copyDefinition(String)

    /// Invoke a specific macOS sharing service by its identifier (e.g.
    /// `com.apple.Notes.SharingExtension`) with the given text. Handled by the effect door via
    /// `NSSharingService(named:).perform`, so Core and the JS host stay testable. Unlike `.showServices`
    /// (a picker), this targets the service directly (e.g. opens the Notes inline popup) and dismisses
    /// the popup.
    case shareService(identifier: String, text: String)

    /// Post a macOS user notification (title/body) via `UNUserNotificationCenter`. Handled by the
    /// effect door so Core and the JS host stay testable; best-effort (skipped if not authorized).
    case notify(title: String, body: String)

    // MARK: - Presentation results (presenter-owned; the effect handler treats these as no-ops)

    /// Surface a transient toast (success/error/info) as a banner or corner badge. Dismisses the
    /// popup by default; `keepVisible` opts out.
    case toast(StatusFeedback)
    /// Hide the popup and ask the user to configure the named action (opens Preferences → ActionEditorPage).
    case openConfiguration(ConfigurationRequest)

    // MARK: - Flow combinators

    /// Perform multiple results in order; the popup hides only if every item dismisses it.
    case sequence([ActionResult])

    // MARK: - Keyboard execution (Phase 8; no execution here)

    /// Send a synthetic key press to the frontmost app.
    case keyPress(KeyPressSpec)
    /// Run a registered shortcut by name with optional input.
    case runShortcut(name: String, input: String?)

    // MARK: - Native File Outputs

    /// Native file output from an action (e.g. generated image, exported file, downloaded media).
    /// Kept open for in-card preview with quick actions to save to default location, copy file, or drag.
    case file(FileOutputPayload)
    /// Explicitly copy the specified file to the system clipboard (as file URL / NSURL).
    case copyFile(URL)
    /// Explicitly save the specified file to the settings-configured default save location.
    case saveFile(URL)

    case none
}

/// Value payload representing a file output produced by an action.
public struct FileOutputPayload: Sendable, Equatable {
    public let url: URL
    public let filename: String?
    public let mimeType: String?
    public let isTemporary: Bool

    /// Creates a file payload and sanitizes any caller-provided display filename.
    public init(url: URL, filename: String? = nil, mimeType: String? = nil, isTemporary: Bool = false) {
        self.url = url
        if let raw = filename {
            let sanitized = (raw as NSString).lastPathComponent
            self.filename = (sanitized.isEmpty || sanitized == "." || sanitized == "..") ? nil : sanitized
        } else {
            self.filename = nil
        }
        self.mimeType = mimeType
        self.isTemporary = isTemporary
    }

    public var displayName: String {
        filename ?? url.lastPathComponent
    }

    public var fileExtension: String {
        (displayName as NSString).pathExtension.lowercased()
    }

    public var isImage: Bool {
        kind == .image
    }
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
        case .text, .file, .showDefinition:
            // Implicit returned text and file outputs are presentation results:
            // kept open for in-card preview; explicit actions (save, copy) or Esc dismiss.
            // The Look Up popover is anchored to the popup panel, so it also stays open.
            return false
        case .sequence(let items):
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        default:
            return true // includes openConfiguration, copyFile, saveFile: hide bar, then execute
        }
    }

    /// Whether this result hands the user a detached, interactive surface (the system Look Up
    /// popover) that stays on screen while the popup remains open. A scroll over such a surface —
    /// the definition itself scrolls — must not auto-dismiss the popup, or the surface anchored to
    /// it goes down with it. Presentation results that render inside the popup (`.text`, `.file`)
    /// don't need this: their `.content` mode already suspends scroll dismissal.
    public var suspendsScrollDismissal: Bool {
        switch self {
        case .showDefinition: return true
        case .sequence(let items): return items.contains(where: \.suspendsScrollDismissal)
        default: return false
        }
    }

    /// True when this result (or any item of a `.sequence`) is a `.toast` — the presenter uses this
    /// to suppress the delivery companion toast so a script toast wins (one toast per run).
    public var containsToast: Bool {
        switch self {
        case .toast: return true
        case .text, .file: return false
        case .sequence(let items): return items.contains(where: \.containsToast)
        default: return false
        }
    }
}
