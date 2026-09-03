// PasteboardCopyEngine.swift
// OpenClip
//
// Standalone, testable clipboard capture engine: archives every pasteboard type, runs a copy
// trigger, polls for a changeCount advance with non-empty string content, then
// restores the original items tagged with the nspasteboard transient markers.
import AppKit
import Core

/// Corrected pasteboard copy capture: archive → trigger → poll → restore.
///
/// Drives the `.menuCopy` / `.keyboardCopy` retrieval modes via
/// `SelectionRetrievalCoordinator.defaultCopyCapture`, so the real clipboard is never left in a
/// copied state.
@MainActor
public struct PasteboardCopyEngine {
    public typealias CopyTrigger = @MainActor () -> Void

    /// Runs `trigger` between archiving the pasteboard and polling for a change.
    ///
    /// - Parameters:
    ///   - pasteboard: The pasteboard to watch (defaults to the system general pasteboard).
    ///   - timeout: Maximum seconds to wait for the pasteboard changeCount to advance and yield text.
    ///     Defaults to a per-app profile: Safari gets a longer budget because its copy path is
    ///     observably slower to stabilize.
    ///   - restoreDelay: Seconds to wait before restoring the archived original items on success.
    ///   - trigger: Performs the actual copy (AX menu press or keyboard event).
    /// - Returns: The copied text plus HTML/RTF when the source app wrote those representations,
    ///   or `nil` when the changeCount never advances or the copied text is empty.
    public func capture(
        pasteboard: NSPasteboard = .general,
        timeout: TimeInterval? = nil,
        restoreDelay: TimeInterval = Constants.pasteboardRestoreDelay,
        trigger: CopyTrigger
    ) async -> TextResult? {
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        trigger()

        let resolvedTimeout = timeout ?? Self.pollingTimeout()
        let pollInterval: TimeInterval = 0.002
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        var result: TextResult?

        while Date() < deadline && !Task.isCancelled {
            if pasteboard.changeCount != initialChangeCount {
                if let candidate = pasteboard.string(forType: .string),
                   Self.hasSelection(candidate) {
                    let html = pasteboard.string(forType: .html) ?? Self.htmlFromRTF(pasteboard)
                    let rtf = pasteboard.string(forType: .rtf)
                    result = TextResult(text: candidate, bounds: nil, html: html, rtf: rtf)
                    break
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        guard let result else {
            if pasteboard.changeCount != initialChangeCount {
                Log.selection.debug("Copy engine: no non-empty pasteboard text within deadline; restoring immediately")
                snapshot.restore(to: pasteboard, transientMarkers: true)
            }
            return nil
        }

        snapshot.restore(to: pasteboard, transientMarkers: true)
        return result
    }

    /// Per-app copy polling timeout. Browsers (Chromium, Safari, Firefox, Arc) need more time
    /// for asynchronous multi-process IPC clipboard operations to stabilize; other apps resolve
    /// within the default budget.
    public static func pollingTimeout(for bundleID: String?) -> TimeInterval {
        guard let bundleID else { return Constants.pasteboardCopyTimeout }
        if isBrowser(bundleID) {
            return Constants.safariPasteboardCopyTimeout
        }
        return Constants.pasteboardCopyTimeout
    }

    public static func isBrowser(_ bundleID: String) -> Bool {
        DefaultAppRules.matchesAny(
            DefaultAppRules.safariGroup + DefaultAppRules.chromiumGroup + DefaultAppRules.firefoxGroup + DefaultAppRules.arcGroup,
            bundleID: bundleID
        )
    }

    private static func pollingTimeout() -> TimeInterval {
        pollingTimeout(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Returns `true` only when `text` is non-nil and contains visible, substantial characters.
    public static func hasSelection(_ text: String?) -> Bool {
        TextSanitizer.isSubstantial(text)
    }

    /// Converts a pasteboard's RTF data into HTML. Apps that copy rich text without an HTML
    /// representation (e.g. Obsidian reading mode) expose the formatting only as RTF; the markdown
    /// converter consumes HTML, so normalize here via NSAttributedString rather than reading the
    /// raw RTF control codes as a string.
    private static func htmlFromRTF(_ pasteboard: NSPasteboard) -> String? {
        guard let rtfData = pasteboard.data(forType: .rtf),
              let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
              let htmlData = try? attributed.data(
                  from: NSRange(location: 0, length: attributed.length),
                  documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
              ) else { return nil }
        return String(data: htmlData, encoding: .utf8)
    }
}
