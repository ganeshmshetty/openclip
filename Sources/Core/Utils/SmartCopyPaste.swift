// SmartCopyPaste.swift
// OpenClip
//
// macOS-style smart cut: which range to delete so cutting a word doesn't leave a double space,
// plus the pasteboard marker NSTextView/WebKit read to re-insert spaces on paste.
// Ranges are UTF-16 (NSRange), matching AX kAXSelectedTextRange.
import Foundation

public enum SmartCopyPaste {
    /// Marker type AppKit and WebKit write on a smart copy/cut; its presence turns on smart insert.
    public static let pasteboardTypeName = "NeXT smart paste pasteboard type"

    /// The range a native ⌘X would delete for `selection` in `text`: the selection plus one adjacent
    /// space when it is a whole word. Returns `selection` unchanged when no extension applies,
    /// or nil when the range is invalid.
    public static func smartDeleteRange(in text: String, selection: NSRange) -> NSRange? {
        let units = Array(text.utf16)
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location + selection.length <= units.count else { return nil }
        guard selection.length > 0 else { return selection }
        let start = selection.location, end = selection.location + selection.length
        if isSpace(units[start]) || isSpace(units[end - 1]) { return selection }

        let before: UInt16? = start > 0 ? units[start - 1] : nil
        let after: UInt16? = end < units.count ? units[end] : nil
        let beforeOK = before.map { isSpace($0) || isNewline($0) } ?? true
        guard beforeOK else { return selection }

        if let after, isSpace(after) {
            return NSRange(location: start, length: selection.length + 1)
        }
        let afterOK = after.map { isNewline($0) || isTrailingPunctuation($0) } ?? true
        if afterOK, let before, isSpace(before) {
            return NSRange(location: start - 1, length: selection.length + 1)
        }
        return selection
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0
    }

    private static func isNewline(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    private static func isTrailingPunctuation(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return ".,;:!?)]}\"'”’…".unicodeScalars.contains(scalar)
    }
}
