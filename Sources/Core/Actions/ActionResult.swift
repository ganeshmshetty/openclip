// ActionResult.swift
// OpenClip
//
// Value enum of action results and platform side-effects. `dismissesPopup` is computed once on the top-level result.
import Foundation

public indirect enum ActionResult: Sendable {
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case openURLInApp(url: URL, appBundleIdentifier: String)
    case copy(String)
    /// Ask the original application to copy its live selection, retaining its native formats.
    case copySelection(SelectionContext)
    case cut(String)
    case paste(String)
    case pasteContent(RichPasteboardPayload)
    case copyContent(RichPasteboardPayload)
    /// Implicitly returned text (JS return, AppleScript output, shell stdout). Carries no delivery decision:
    /// the "When an action returns text" preference picks preview/paste/copy. Explicit effects are never re-decided.
    case text(String)
    /// A typed inline color: shown as a swatch card with explicit Copy/Save; automatic delivery is Show-only.
    case color(InlineColor)
    /// A typed inline emoji: shown large in the card, delivered as text on Paste/Copy.
    case emoji(String)
    /// Carrier for a validated typed inline return; the inline evaluator converts it to a
    /// deliverable result after checking the action's declared output kind.
    case inlineValue(InlineResultValue)
    case showServices(String)

    /// Look Up popover for `word`. Nothing is copied and the popup stays open to keep the anchor.
    case showDefinition(String)

    /// Copies the headless dictionary definition of `word`; returned by Define on a force-copy click.
    case copyDefinition(String)

    /// Sends `text` directly to the sharing service `identifier` and dismisses the popup. Unlike `.showServices`, no picker.
    case shareService(identifier: String, text: String)

    /// macOS user notification; best-effort, skipped when not authorised.
    case notify(title: String, body: String)

    // MARK: - Presentation results (presenter-owned; the effect handler treats these as no-ops)

    /// Transient toast; dismisses the popup unless `keepVisible`.
    case toast(StatusFeedback)
    /// Hide the popup and ask the user to configure the named action (opens Preferences → ActionEditorPage).
    case openConfiguration(ConfigurationRequest)

    // MARK: - Flow combinators

    /// Perform multiple results in order; the popup hides only if every item dismisses it.
    case sequence([ActionResult])

    // MARK: - Keyboard execution (Phase 8; no execution here)

    case keyPress(KeyPressSpec)
    case runShortcut(name: String, input: String?)

    // MARK: - Native File Outputs

    /// File output shown in-card, with quick actions to save, copy or drag.
    case file(FileOutputPayload)
    case copyFile(URL)
    /// Saves to the configured default location.
    case saveFile(URL)

    case none
}

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
    /// Computed on the top-level result: a `.toast` dismisses unless `keepVisible`; a `.sequence`
    /// dismisses only when non-empty and every item does.
    public var dismissesPopup: Bool {
        switch self {
        case .toast(let feedback):
            return !feedback.keepVisible
        case .text, .file, .showDefinition, .color, .emoji:
            // Kept open for in-card preview; the Look Up popover is anchored to the panel, so it stays too.
            return false
        case .sequence(let items):
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        default:
            return true // includes openConfiguration, copyFile, saveFile: hide bar, then execute
        }
    }

    /// A scroll over the Look Up popover must not dismiss the popup, or the popover goes down with it.
    public var suspendsScrollDismissal: Bool {
        switch self {
        case .showDefinition: return true
        case .sequence(let items): return items.contains(where: \.suspendsScrollDismissal)
        default: return false
        }
    }

    /// Lets a script toast win over the delivery companion toast (one toast per run).
    public var containsToast: Bool {
        switch self {
        case .toast: return true
        case .text, .file, .color, .emoji: return false
        case .sequence(let items): return items.contains(where: \.containsToast)
        default: return false
        }
    }
}
