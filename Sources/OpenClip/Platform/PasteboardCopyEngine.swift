// PasteboardCopyEngine.swift
// OpenClip
//
// Standalone, testable clipboard capture engine: archives every pasteboard type, runs a copy
// trigger, polls for a changeCount advance, verifies the string content actually changed, then
// restores the original items tagged with the nspasteboard transient markers.
import AppKit
import Core

/// Corrected pasteboard copy capture: archive → trigger → poll → verify → restore.
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
    ///   - timeout: Maximum seconds to wait for the pasteboard changeCount to advance.
    ///   - restoreDelay: Seconds to wait before restoring the archived original items on success.
    ///   - trigger: Performs the actual copy (AX menu press or keyboard event).
    /// - Returns: The new string on the pasteboard, or `nil` when the changeCount never advances,
    ///   the copied string is empty, or the copied string equals the archived original.
    public func captureString(
        pasteboard: NSPasteboard = .general,
        timeout: TimeInterval = Constants.pasteboardCopyTimeout,
        restoreDelay: TimeInterval = Constants.pasteboardRestoreDelay,
        trigger: CopyTrigger
    ) async -> String? {
        let savedItems = Self.archive(pasteboard)
        let archivedString = pasteboard.string(forType: .string)
        let initialChangeCount = pasteboard.changeCount

        trigger()

        // Poll every 2 ms up to `timeout` for the changeCount to advance. A deadline loop (rather
        // than the OnceResume/TaskBox watchdog) is the right shape here: the trigger is a
        // synchronous MainActor closure, so there is no worker task racing a deadline that could
        // double-resume a continuation to guard against. The deadline bounds the loop regardless.
        let pollInterval: TimeInterval = 0.002
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !Task.isCancelled {
            if pasteboard.changeCount != initialChangeCount { break }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        guard pasteboard.changeCount != initialChangeCount else {
            Log.selection.debug("Copy engine: changeCount did not advance; restoring immediately")
            Self.restore(pasteboard, items: savedItems)
            return nil
        }

        let text = pasteboard.string(forType: .string)
        guard Self.hasSelection(text), text != archivedString else {
            Log.selection.debug("Copy engine: copied string empty or unchanged; restoring immediately")
            Self.restore(pasteboard, items: savedItems)
            return nil
        }

        // Keep the captured string readable for `restoreDelay`, then put the original back. Skip
        // the restore if the pasteboard was written to again in the meantime (e.g. a user copy).
        let changeCountAfterRead = pasteboard.changeCount
        Task { @MainActor [pasteboard, savedItems, changeCountAfterRead, restoreDelay] in
            try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard pasteboard.changeCount == changeCountAfterRead else { return }
            Self.restore(pasteboard, items: savedItems, transientMarkers: true)
        }

        return text
    }

    /// Returns `true` only when `text` is non-nil and trims to something non-empty.
    public static func hasSelection(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Copies every type's data off every pasteboard item so the original content can be restored
    /// verbatim (mirrors `ActionResultHandler.backupPasteboard`).
    private static func archive(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }

    /// Writes the archived items back. When `transientMarkers` is true, tags each item with the
    /// nspasteboard transient / auto-generated markers (empty data) so clipboard managers skip the
    /// restore as a user-visible copy.
    private static func restore(
        _ pasteboard: NSPasteboard,
        items: [NSPasteboardItem],
        transientMarkers: Bool = false
    ) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        if transientMarkers {
            let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")
            let autoGeneratedType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.AutoGeneratedType")
            for item in items {
                item.setData(Data(), forType: transientType)
                item.setData(Data(), forType: autoGeneratedType)
            }
        }
        pasteboard.writeObjects(items)
    }
}
