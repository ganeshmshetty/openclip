// MarkdownPresence.swift
// OpenClip
//
// Cheap signal for "this result is Markdown-formatted", used by the result card to decide whether
// to render the body as Markdown. Detection only, not parsing: a false positive costs a slightly
// restyled card, a false negative keeps today's plain text. Line-anchored constructs and paired
// inline markers are checked outside fenced code blocks so shell output (`# comment`, `*` globs)
// does not read as formatting.
import Foundation

public enum MarkdownPresence {
    /// Beyond this the scan is skipped; huge outputs stay plain.
    public static let maxScanLength = 20_000

    public static func isMarkdown(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= maxScanLength else { return false }

        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence { return true }
                inFence = true
                continue
            }
            if inFence { continue }
            if isBlockMarker(trimmed) { return true }
        }
        if inFence { return true }
        return hasPairedInlineMarker(text)
    }

    private static func isBlockMarker(_ line: String) -> Bool {
        // ATX heading: "# Title" … "###### Title". A lowercase word right after the hashes reads
        // as a shell comment ("# comment line"), not a heading. CJK has no case, so it always counts.
        if line.hasPrefix("#") {
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                let word = String(line.dropFirst(hashes + 1).prefix(while: { $0.isLetter }))
                let hasCaselessScript = word.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
                if word.isEmpty || hasCaselessScript || word != word.lowercased() { return true }
            }
        }
        // Bullet list: "- item", "* item", "+ item". A bare "*" requires a letter/digit after the
        // space so shell globs ("ls * .swift") don't read as list items.
        if let first = line.first, "-+".contains(first), line.dropFirst().first == " " { return true }
        if line.hasPrefix("* "), let next = line.dropFirst(2).first, next.isLetter || next.isNumber { return true }
        // Ordered list: "1. item", "2) item"
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 9 {
            let rest = line.dropFirst(digits.count)
            if let punct = rest.first, punct == "." || punct == ")", rest.dropFirst().first == " " { return true }
        }
        // Blockquote, thematic break, table row
        if line.hasPrefix("> ") { return true }
        if line.count >= 3, Set(line) == ["-"] || Set(line) == ["*"] || Set(line) == ["_"] { return true }
        if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 2 { return true }
        return false
    }

    /// Paired `**bold**` or `__bold__`, single `*italic*`/`_italic_`, `` `code` ``, `[link](url)`.
    private static func hasPairedInlineMarker(_ text: String) -> Bool {
        if text.contains("**"), pairedCount(of: "**", in: text) >= 2 { return true }
        if text.contains("__"), pairedCount(of: "__", in: text) >= 2 { return true }
        if text.contains("`"), text.filter({ $0 == "`" }).count >= 2 { return true }
        if let range = text.range(of: "]("), text[text.startIndex..<range.lowerBound].contains("[") { return true }
        if hasSingleAsteriskPair(text) { return true }
        return false
    }

    private static func pairedCount(of marker: String, in text: String) -> Int {
        var count = 0
        var search = text[...]
        while let range = search.range(of: marker) {
            count += 1
            search = search[range.upperBound...]
        }
        return count
    }

    /// `*italic*` needs a word boundary on both sides, so `*.swift` globs and `2*3*4` stay plain.
    private static func hasSingleAsteriskPair(_ text: String) -> Bool {
        let chars = Array(text)
        var open: Int?
        for (i, ch) in chars.enumerated() where ch == "*" {
            if i > 0, chars[i - 1] == "*" { continue }
            if i + 1 < chars.count, chars[i + 1] == "*" { continue }
            if let start = open {
                let closesWord = i + 1 >= chars.count || chars[i + 1] == " " || chars[i + 1] == "\n"
                    || ".,;:!?)]}".contains(chars[i + 1])
                if i > start + 1, chars[i - 1] != " ", chars[start + 1] != " ", closesWord { return true }
                open = nil
            } else if i + 1 < chars.count, chars[i + 1] != " ", i == 0 || chars[i - 1] == " " || chars[i - 1] == "\n" {
                open = i
            }
        }
        return false
    }
}