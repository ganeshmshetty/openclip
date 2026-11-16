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

    /// Text to actually insert so a pasted word doesn't glue onto its neighbours, for fields that
    /// ignore the smart-paste marker (e.g. HTML inputs). `before`/`after` are the characters around
    /// the insertion range (nil at start/end of text).
    public static func smartInsertText(_ text: String, before: Character?, after: Character?) -> String {
        guard let first = text.utf16.first, let last = text.utf16.last,
              !isSpace(first), !isNewline(first), !isSpace(last), !isNewline(last) else { return text }
        var result = text
        if let before, isWordish(before) { result = " " + result }
        if let after, isWordish(after) { result += " " }
        return result
    }

    /// `smartInsertText` using the characters around `selection` in `value`.
    public static func smartInsertText(_ text: String, into value: String, selection: NSRange) -> String? {
        let ns = value as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location + selection.length <= ns.length else { return nil }
        let end = selection.location + selection.length
        let before = selection.location > 0
            ? (ns.substring(with: ns.rangeOfComposedCharacterSequence(at: selection.location - 1))).last : nil
        let after = end < ns.length ? ns.substring(with: ns.rangeOfComposedCharacterSequence(at: end)).first : nil
        return smartInsertText(text, before: before, after: after)
    }

    private static func isWordish(_ char: Character) -> Bool {
        char.isLetter || char.isNumber
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
