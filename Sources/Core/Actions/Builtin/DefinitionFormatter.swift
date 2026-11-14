// DefinitionFormatter.swift
// OpenClip
//
// Restores line structure to the single-line definition blob returned by DictionaryServices.
import Foundation

/// Formats `DCSCopyTextDefinition`'s flattened definition into readable paragraphs.
///
/// The system concatenates headword, phonetics, senses, examples, derivatives and origin with
/// `|`, `•` and uppercase labels. This only restores line structure: no text is added, removed or
/// reordered, and the output stays plain so Copy keeps clean content. Unrecognized input passes
/// through unchanged, which keeps short or non-system definitions intact.
public enum DefinitionFormatter {
    private static let sectionLabels = [
        "DERIVATIVES", "ORIGIN", "PHRASES", "PHRASAL VERBS", "USAGE",
        "GRAMMAR", "SYNONYMS", "ANTONYMS", "COMPARE", "SEE ALSO"
    ]

    /// Longest first so "phrasal verb" wins over "verb".
    private static let partsOfSpeech = [
        "phrasal verb", "auxiliary verb", "abbreviation", "interjection", "conjunction",
        "preposition", "determiner", "adjective", "exclamation", "pronoun", "adverb",
        "prefix", "suffix", "noun", "verb"
    ]

    public static func format(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let parts = splitHeader(trimmed)
        let body = parts.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return parts.head }

        let sections = bodySections(body).map(formatSection)
        var result = parts.head.isEmpty ? sections.joined(separator: "\n\n")
                                         : parts.head + "\n\n" + sections.joined(separator: "\n\n")
        result = splitSectionLabels(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `headword syllables | phonetics | part of speech …` — the first two ` | ` delimit the head.
    private static func splitHeader(_ text: String) -> (head: String, body: String) {
        guard let first = text.range(of: " | "),
              let second = text.range(of: " | ", range: first.upperBound..<text.endIndex) else {
            return ("", text)
        }
        let head = text[..<second.lowerBound].trimmingCharacters(in: .whitespaces)
        let body = text[second.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !body.isEmpty else { return ("", text) }
        return (head, body)
    }

    /// A later part of speech starts after the previous sense's full stop
    /// ("… dismal thinkings. adjective [attributive] …"). Splitting the body into sections first
    /// lets each part of speech restart its own sense numbering.
    private static func bodySections(_ body: String) -> [Substring] {
        var cuts = Set<String.Index>([body.startIndex])
        for part in partsOfSpeech {
            var search = body.startIndex
            while let range = body.range(of: ". \(part) ", range: search..<body.endIndex) {
                cuts.insert(body.index(range.lowerBound, offsetBy: 2))
                search = range.upperBound
            }
        }
        let starts = cuts.sorted()
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : body.endIndex
            return body[start..<end]
        }
    }

    private static func formatSection(_ section: Substring) -> String {
        var text = section.trimmingCharacters(in: .whitespacesAndNewlines)

        // The leading part of speech becomes its own heading.
        let lower = text.lowercased()
        if let part = partsOfSpeech.first(where: { lower.hasPrefix($0) }) {
            let end = text.index(text.startIndex, offsetBy: part.count)
            let rest = text[end...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                text = part + "\n\n" + rest
            }
        }

        text = text.replacingOccurrences(of: " • ", with: "\n\n• ")
        return splitNumberedSenses(text)
    }

    /// Splits ` 1 `, ` 2 ` … into a numbered list, but only when the sequence is real: a lone
    /// number in prose (" 1 ") is left alone. Each section starts at 1.
    private static func splitNumberedSenses(_ text: String) -> String {
        var output = ""
        var remaining = Substring(text)
        var expected = 1
        while let marker = senseMarker(expected, in: remaining) {
            let after = remaining[marker.upperBound...]
            guard expected > 1 || senseMarker(2, in: after) != nil else { break }
            output += remaining[..<marker.lowerBound]
            while output.last?.isWhitespace == true { output.removeLast() }
            output += "\n\n\(expected). "
            remaining = after
            expected += 1
        }
        return output + remaining
    }

    /// The number can follow a space or start a paragraph (the part-of-speech split leaves it
    /// at the head of a line).
    private static func senseMarker(_ number: Int, in text: Substring) -> Range<Substring.Index>? {
        let token = "\(number)"
        if text.hasPrefix("\(token) ") {
            return text.startIndex..<text.index(text.startIndex, offsetBy: token.count + 1)
        }
        if let range = text.range(of: "\n\(token) ") {
            return range
        }
        return text.range(of: " \(token) ")
    }

    private static func splitSectionLabels(_ text: String) -> String {
        var result = text
        for label in sectionLabels {
            result = result.replacingOccurrences(of: " \(label) ", with: "\n\n\(label)\n")
        }
        return result
    }
}
