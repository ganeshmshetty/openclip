// TextSanitizer.swift
// OpenClip
//
// Pure domain utility for sanitizing and validating selected text across apps,
// removing invisible Unicode artifacts, control characters, zero-width spaces,
// and terminal grid padding.
import Foundation

public enum TextSanitizer: Sendable {
    /// Non-printable, zero-width, formatting, and invisible character set
    public static let invisibleCharacterSet: CharacterSet = {
        var set = CharacterSet()
        // Control characters (0x00...0x1F, 0x7F...0x9F)
        set.formUnion(.controlCharacters)
        // Whitespace and newlines
        set.formUnion(.whitespacesAndNewlines)
        // Specific Unicode zero-width, formatting, and non-printable characters
        let specialScalars: [Unicode.Scalar] = [
            "\u{0000}", // Null byte
            "\u{00A0}", // Non-breaking space
            "\u{200B}", // Zero-width space
            "\u{200C}", // Zero-width non-joiner
            "\u{200D}", // Zero-width joiner
            "\u{200E}", // Left-to-right mark
            "\u{200F}", // Right-to-left mark
            "\u{202A}", // Left-to-right embedding
            "\u{202B}", // Right-to-left embedding
            "\u{202C}", // Pop directional formatting
            "\u{202D}", // Left-to-right override
            "\u{202E}", // Right-to-left override
            "\u{2060}", // Word joiner
            "\u{FEFF}"  // Zero-width no-break space / BOM
        ]
        for scalar in specialScalars {
            set.insert(scalar)
        }
        return set
    }()

    /// Returns `true` only if `text` contains at least one visible, substantial character.
    public static func isSubstantial(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.unicodeScalars.contains { !invisibleCharacterSet.contains($0) }
    }

    /// Trims leading and trailing whitespace, newlines, and invisible characters from `text`.
    public static func sanitize(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: invisibleCharacterSet)
        return trimmed.isEmpty ? nil : trimmed
    }
}
