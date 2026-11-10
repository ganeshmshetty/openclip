// TextLanguageDetector.swift
// OpenClip
//
// Identifies the language of selected text for spelling suggestions and for extension runtimes.
// Short selections are not handed to NLLanguageRecognizer: a single word is a weak signal and is
// often labeled with the UI language. Those use spelling dictionaries. Longer text uses the
// recognizer, with spelling as a fallback when recognition is unsure.
import Foundation
import NaturalLanguage

public struct SpellLanguageAssessment: Sendable, Equatable {
    public let language: String
    /// False when this language has no dictionary, so it must not count as "spelled correctly".
    public let checked: Bool
    public let misspelled: Bool
    public let completions: [String]
    public let guesses: [String]

    public init(language: String, checked: Bool, misspelled: Bool, completions: [String], guesses: [String]) {
        self.language = language
        self.checked = checked
        self.misspelled = misspelled
        self.completions = completions
        self.guesses = guesses
    }
}

/// Platform spell checker. Core stays free of AppKit; the app installs one at launch.
/// The type is `Sendable` so actions can hold one; every method runs on the main actor
/// because `NSSpellChecker` is main-thread-only.
public protocol TextSpellChecking: AnyObject, Sendable {
    @MainActor func preferredLanguages() -> [String]
    @MainActor func assessments(for text: String) -> [SpellLanguageAssessment]
}

@MainActor
public enum TextSpellCheckerRegistry {
    public static var checker: (any TextSpellChecking)?
}

public enum TextLanguageDetector {
    /// First stretch of a long selection. Language id does not need the rest, and spell-checking
    /// a multi-megabyte paste on the main thread would stall the popup.
    private static let recognitionSampleLength = 400
    private static let minimumRecognitionConfidence = 0.5
    private static let longFormWordCount = 3
    private static let longFormLetterCount = 40

    /// True when every checked preferred language rejects `assessments`.
    /// With no checked dictionary the word is treated as misspelled so a "hide correct words"
    /// gate cannot hide every suggestion just because spell checking was unavailable.
    public static func isMisspelledInAllPreferred(_ assessments: [SpellLanguageAssessment]) -> Bool {
        let checked = assessments.filter(\.checked)
        guard !checked.isEmpty else { return true }
        return checked.allSatisfy(\.misspelled)
    }

    /// Completions (or guesses, when a language has no completions) from the best-fitting
    /// language. When that language has nothing left after filtering, the first preferred
    /// language is tried. At most `limit` unique words, excluding `word` itself.
    public static func suggestions(for word: String, assessments: [SpellLanguageAssessment], limit: Int = 4) -> [String] {
        guard limit > 0 else { return [] }
        for assessment in suggestionSources(for: word, assessments: assessments) {
            let list = filteredSuggestions(from: assessment, excluding: word, limit: limit)
            if !list.isEmpty { return list }
        }
        return []
    }

    /// BCP-47-style tag of `text` (`en`, `sv`, `en_US`, `zh-Hans`), or nil when it cannot be told.
    /// A word that is misspelled in every preferred language stays nil: a guess is not a detection.
    @MainActor
    public static func textLanguageCode(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains(where: { $0.isLetter }) else { return nil }
        let sample = sample(trimmed)
        let checker = TextSpellCheckerRegistry.checker
        if prefersSpellCheck(for: sample) {
            return languageOfCorrectSpelling(checker?.assessments(for: sample) ?? [])
        }
        if let recognized = dominantLanguageCode(for: sample, hints: checker?.preferredLanguages() ?? []) {
            return recognized
        }
        return languageOfCorrectSpelling(checker?.assessments(for: sample) ?? [])
    }

    /// Sets `OPENCLIP_TEXT_LANGUAGE` when detection succeeds and removes it otherwise,
    /// including a value inherited from the parent environment.
    @MainActor
    static func assignTextLanguage(of text: String, to environment: inout [String: String]) {
        if let code = textLanguageCode(for: text), !code.isEmpty {
            environment[Constants.envVarTextLanguage] = code
        } else {
            environment.removeValue(forKey: Constants.envVarTextLanguage)
        }
    }

    static func prefersSpellCheck(for text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        if tokens.count >= longFormWordCount { return false }
        return letterCount(in: text, limit: longFormLetterCount) < longFormLetterCount
    }

    private static func languageOfCorrectSpelling(_ assessments: [SpellLanguageAssessment]) -> String? {
        let code = assessments.first { $0.checked && !$0.misspelled }?.language
        guard let code, !code.isEmpty else { return nil }
        return code
    }

    private static func suggestionSources(for word: String, assessments: [SpellLanguageAssessment]) -> [SpellLanguageAssessment] {
        guard let bestCode = bestFittingLanguage(for: word, in: assessments),
              let best = assessments.first(where: { $0.language == bestCode }) else {
            return Array(assessments.prefix(1))
        }
        guard let first = assessments.first, first.language != best.language else {
            return [best]
        }
        return [best, first]
    }

    /// A language that spells the word correctly wins, in preferred order.
    /// When every language rejects it, the one with the strongest completion list wins,
    /// and ties keep the earlier language.
    static func bestFittingLanguage(for word: String, in assessments: [SpellLanguageAssessment]) -> String? {
        let checked = assessments.filter(\.checked)
        let pool = checked.isEmpty ? assessments : checked
        guard let first = pool.first else { return nil }
        let correct = pool.filter { !$0.misspelled }
        if let match = correct.first { return match.language }
        var best = first
        var bestScore = suggestionScore(first, word: word)
        for item in pool.dropFirst() {
            let score = suggestionScore(item, word: word)
            if score > bestScore {
                best = item
                bestScore = score
            }
        }
        return best.language
    }

    private static func suggestionScore(_ assessment: SpellLanguageAssessment, word: String) -> Int {
        let prefix = word.lowercased()
        let prefixHits = assessment.completions.reduce(into: 0) { count, candidate in
            if candidate.lowercased().hasPrefix(prefix) { count += 1 }
        }
        if prefixHits > 0 { return 1_000 + prefixHits }
        if !assessment.completions.isEmpty { return 100 + assessment.completions.count }
        if !assessment.guesses.isEmpty { return 10 + min(assessment.guesses.count, 20) }
        return 0
    }

    private static func filteredSuggestions(from assessment: SpellLanguageAssessment, excluding word: String, limit: Int) -> [String] {
        let raw = assessment.completions.isEmpty ? assessment.guesses : assessment.completions
        var unique: [String] = []
        let excluded = word.lowercased()
        for candidate in raw {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.lowercased() != excluded && !unique.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                unique.append(trimmed)
            }
            if unique.count >= limit { break }
        }
        return unique
    }

    private static func sample(_ text: String) -> String {
        guard text.count > recognitionSampleLength else { return text }
        let end = text.index(text.startIndex, offsetBy: recognitionSampleLength)
        return String(text[..<end])
    }

    private static func letterCount(in text: String, limit: Int) -> Int {
        var count = 0
        for character in text where character.isLetter {
            count += 1
            if count >= limit { break }
        }
        return count
    }

    private static func dominantLanguageCode(for text: String, hints: [String]) -> String? {
        let recognizer = NLLanguageRecognizer()
        var priors: [NLLanguage: Double] = [:]
        for tag in hints {
            priors[hintLanguage(for: tag)] = 0.15
        }
        if !priors.isEmpty {
            recognizer.languageHints = priors
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 5)[language] ?? 0
        guard confidence >= minimumRecognitionConfidence else { return nil }
        let code = language.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    private static func hintLanguage(for tag: String) -> NLLanguage {
        let dashed = tag.replacingOccurrences(of: "_", with: "-")
        let lower = dashed.lowercased()
        if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") {
            return NLLanguage(rawValue: "zh-Hant")
        }
        if lower.hasPrefix("zh") {
            return NLLanguage(rawValue: "zh-Hans")
        }
        let primary = dashed.split(separator: "-").first.map { String($0).lowercased() } ?? lower
        return NLLanguage(rawValue: primary)
    }
}
