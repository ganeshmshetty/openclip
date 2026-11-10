// SystemTextSpellChecker.swift
// OpenClip
//
// NSSpellChecker adapter for TextLanguageDetector. The older completions/guesses methods use the
// single language from setLanguage when `language` is nil; automatic identification only applies
// to the unified text-checking API. Each preferred spelling language is passed explicitly.
import AppKit
import Core

@MainActor
public final class SystemTextSpellChecker: TextSpellChecking {
    public static let shared = SystemTextSpellChecker()

    private struct AssessmentCache {
        let text: String
        let languages: [String]
        let value: [SpellLanguageAssessment]
    }

    /// Whether `language` flags a nonsense probe. Languages that never do still report "not misspelled".
    private var unknownWordFlags: [String: Bool] = [:]

    /// The popup asks for the same word while building one popup; keep the last result so only the
    /// first call pays for `NSSpellChecker`.
    private var assessmentCache: AssessmentCache?

    public func preferredLanguages() -> [String] {
        let checker = NSSpellChecker.shared
        let preferred = checker.userPreferredLanguages.filter { !$0.isEmpty }
        if !preferred.isEmpty { return preferred }
        let current = checker.language()
        if !current.isEmpty { return [current] }
        return ["en"]
    }

    public func assessments(for text: String) -> [SpellLanguageAssessment] {
        let available = Set(NSSpellChecker.shared.availableLanguages)
        let usable = Self.unique(preferredLanguages()).filter { Self.isAvailable($0, available: available) }
        let probe = Self.unknownWordProbe(for: text)
        // The legacy path resolves `NSSpellChecker.language()` per call, so caching it by text alone
        // would keep a stale language after the user changes the spelling language.
        if usable.isEmpty {
            return [legacyAssessment(for: text, probe: probe)]
        }
        if let cached = assessmentCache, cached.text == text, cached.languages == usable {
            return cached.value
        }
        let value = usable.map { assess(text, language: $0, probe: probe) }
        assessmentCache = AssessmentCache(text: text, languages: usable, value: value)
        return value
    }

    private func assess(_ text: String, language: String, probe: String?) -> SpellLanguageAssessment {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: text.utf16.count)
        var wordCount = 0
        let misspelledRange = checker.checkSpelling(
            of: text,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        let completions = checker.completions(
            forPartialWordRange: range,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        // Guesses are only read when completions are empty; asking every dictionary for them was
        // the most expensive part of the popup path.
        let guesses = completions.isEmpty
            ? checker.guesses(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: 0) ?? []
            : []
        let misspelled = misspelledRange.location != NSNotFound
        return SpellLanguageAssessment(
            language: language,
            checked: dictionaryChecked(
                wordCount: wordCount,
                misspelled: misspelled,
                hasCompletions: !completions.isEmpty,
                language: language,
                probe: probe
            ),
            misspelled: misspelled,
            completions: completions,
            guesses: guesses
        )
    }

    /// No preferred dictionary is installed. Keep the previous nil-language query so a machine
    /// without a matching dictionary still returns the completions it returned before.
    private func legacyAssessment(for text: String, probe: String?) -> SpellLanguageAssessment {
        let checker = NSSpellChecker.shared
        let current = checker.language()
        let language = current.isEmpty ? (preferredLanguages().first ?? "en") : current
        let range = NSRange(location: 0, length: text.utf16.count)
        var wordCount = 0
        let misspelledRange = checker.checkSpelling(
            of: text,
            startingAt: 0,
            language: nil,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: &wordCount
        )
        let completions = checker.completions(
            forPartialWordRange: range,
            in: text,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        let guesses = completions.isEmpty
            ? checker.guesses(forWordRange: range, in: text, language: nil, inSpellDocumentWithTag: 0) ?? []
            : []
        let misspelled = misspelledRange.location != NSNotFound
        return SpellLanguageAssessment(
            language: language,
            checked: dictionaryChecked(
                wordCount: wordCount,
                misspelled: misspelled,
                hasCompletions: !completions.isEmpty,
                language: nil,
                probe: probe
            ),
            misspelled: misspelled,
            completions: completions,
            guesses: guesses
        )
    }

    /// `NSSpellChecker` reports no misspelling for a language that never tests the word's script, and may
    /// still fill guesses from another language. That is not a dictionary accept. A misspelling, a
    /// completion list, or a language that does flag a nonsense word of the same script is.
    static func countsAsDictionaryHit(wordCount: Int, misspelled: Bool, hasCompletions: Bool, flagsUnknownWords: Bool) -> Bool {
        if wordCount == 0 { return false }
        if misspelled || hasCompletions { return true }
        return flagsUnknownWords
    }

    private func dictionaryChecked(wordCount: Int, misspelled: Bool, hasCompletions: Bool, language: String?, probe: String?) -> Bool {
        let flagsUnknownWords: Bool
        if misspelled || hasCompletions || wordCount == 0 {
            flagsUnknownWords = false
        } else if let probe {
            flagsUnknownWords = self.flagsUnknownWords(language, probe: probe)
        } else {
            // No probe means no dictionary was shown to check this script. Treating that as a hit
            // made numbers and unsupported scripts report the first preferred language.
            flagsUnknownWords = false
        }
        return Self.countsAsDictionaryHit(
            wordCount: wordCount,
            misspelled: misspelled,
            hasCompletions: hasCompletions,
            flagsUnknownWords: flagsUnknownWords
        )
    }

    private func flagsUnknownWords(_ language: String?, probe: String) -> Bool {
        let key = (language ?? "") + "\t" + probe
        if let cached = unknownWordFlags[key] { return cached }
        let range = NSSpellChecker.shared.checkSpelling(
            of: probe,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let flags = range.location != NSNotFound
        unknownWordFlags[key] = flags
        return flags
    }

    private enum LetterScript {
        case latin, cyrillic, greek, arabic, hebrew, devanagari
    }

    private static func unknownWordProbe(for text: String) -> String? {
        switch dominantScript(of: text) {
        case .latin: return "xyzzyplugh"
        case .cyrillic: return "щяюыэъ"
        case .greek: return "ψξωθφχ"
        case .arabic: return "ؼڸڽڿ"
        case .hebrew: return "װױײױ"
        case .devanagari: return "क़ख़ग़ज़"
        case nil: return nil
        }
    }

    private static func dominantScript(of text: String) -> LetterScript? {
        var counts: [LetterScript: Int] = [:]
        for scalar in text.unicodeScalars {
            guard let script = letterScript(of: scalar) else { continue }
            counts[script, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private static func letterScript(of scalar: Unicode.Scalar) -> LetterScript? {
        guard scalar.properties.isAlphabetic else { return nil }
        switch scalar.value {
        case 0x0041...0x024F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF:
            return .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF:
            return .greek
        case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            return .cyrillic
        case 0x0590...0x05FF:
            return .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
            return .arabic
        case 0x0900...0x097F:
            return .devanagari
        default:
            return nil
        }
    }

    private static func unique(_ languages: [String]) -> [String] {
        var seen = Set<String>()
        return languages.filter { seen.insert($0).inserted }
    }

    static func isAvailable(_ language: String, available: Set<String>) -> Bool {
        guard !available.isEmpty else { return false }
        if available.contains(language) { return true }
        let underscore = language.replacingOccurrences(of: "-", with: "_")
        let dashed = language.replacingOccurrences(of: "_", with: "-")
        if available.contains(underscore) || available.contains(dashed) { return true }
        let primary = underscore.split(separator: "_").first.map(String.init) ?? underscore
        if available.contains(primary) { return true }
        return available.contains { candidate in
            let normalized = candidate.replacingOccurrences(of: "-", with: "_")
            let candidatePrimary = normalized.split(separator: "_").first.map(String.init) ?? normalized
            return candidatePrimary == primary
        }
    }
}
