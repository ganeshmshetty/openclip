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
        if usable.isEmpty {
            return [legacyAssessment(for: text)]
        }
        return usable.map { assess(text, language: $0) }
    }

    private func assess(_ text: String, language: String) -> SpellLanguageAssessment {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: text.utf16.count)
        let misspelledRange = checker.checkSpelling(
            of: text,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let completions = checker.completions(
            forPartialWordRange: range,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        let guesses = checker.guesses(
            forWordRange: range,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []
        return SpellLanguageAssessment(
            language: language,
            checked: true,
            misspelled: misspelledRange.location != NSNotFound,
            completions: completions,
            guesses: guesses
        )
    }

    /// No preferred dictionary is installed. Keep the previous nil-language query so a machine
    /// without a matching dictionary still returns the completions it returned before.
    private func legacyAssessment(for text: String) -> SpellLanguageAssessment {
        let checker = NSSpellChecker.shared
        let current = checker.language()
        let language = current.isEmpty ? (preferredLanguages().first ?? "en") : current
        let range = NSRange(location: 0, length: text.utf16.count)
        let misspelledRange = checker.checkSpelling(
            of: text,
            startingAt: 0,
            language: nil,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        let completions = checker.completions(
            forPartialWordRange: range,
            in: text,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        let guesses = checker.guesses(
            forWordRange: range,
            in: text,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        return SpellLanguageAssessment(
            language: language,
            checked: true,
            misspelled: misspelledRange.location != NSNotFound,
            completions: completions,
            guesses: guesses
        )
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
