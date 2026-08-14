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
    /// - Returns: The new string on the pasteboard, or `nil` when the changeCount never advances
    ///   or the copied string is empty.
    public func captureString(
        pasteboard: NSPasteboard = .general,
        timeout: TimeInterval? = nil,
        restoreDelay: TimeInterval = Constants.pasteboardRestoreDelay,
        trigger: CopyTrigger
    ) async -> String? {
        let snapshot = PasteboardSnapshot.capture(pasteboard)
        let initialChangeCount = pasteboard.changeCount

        trigger()

        let resolvedTimeout = timeout ?? Self.pollingTimeout()
        let pollInterval: TimeInterval = 0.002
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        var text: String?

        // A changeCount advance alone is not enough: some apps write a transient/empty string while
        // the pasteboard is still being updated (or a clipboard manager is racing the same copy), so
        // keep polling until non-empty text appears or the deadline passes.
        while Date() < deadline && !Task.isCancelled {
            if pasteboard.changeCount != initialChangeCount {
                if let candidate = pasteboard.string(forType: .string),
                   Self.hasSelection(candidate) {
                    text = candidate
                    break
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        guard let text else {
            Log.selection.debug("Copy engine: no non-empty pasteboard text within deadline; restoring immediately")
            snapshot.restore(to: pasteboard, transientMarkers: true)
            return nil
        }

        // Restore the original pasteboard synchronously before returning. The captured string is
        // already held in memory, so there is no reason to leave it on the general pasteboard (the
        // reference implementation restores with a zero interval after the poll completes). An async
        // delayed restore is both unnecessary and unreliable here: it races later clipboard writes
        // and can leave the copied text visible in clipboard managers.
        snapshot.restore(to: pasteboard, transientMarkers: true)

        return text
    }

    /// Per-app copy polling timeout. Safari is the observed outlier needing more time for its
    /// selected-text copy to stabilize; all other apps resolve within the default budget.
    private static func pollingTimeout() -> TimeInterval {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return bundleID == "com.apple.Safari"
            ? Constants.safariPasteboardCopyTimeout
            : Constants.pasteboardCopyTimeout
    }

    /// Returns `true` only when `text` is non-nil and contains visible, substantial characters.
    public static func hasSelection(_ text: String?) -> Bool {
        TextSanitizer.isSubstantial(text)
    }
}
