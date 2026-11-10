import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class StubTextSpellChecker: TextSpellChecking {
    let languages: [String]
    let reports: [SpellLanguageAssessment]

    init(languages: [String], reports: [SpellLanguageAssessment]) {
        self.languages = languages
        self.reports = reports
    }

    func preferredLanguages() -> [String] { languages }

    func assessments(for text: String) -> [SpellLanguageAssessment] { reports }
}

@MainActor
final class TextLanguageDetectorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        TextSpellCheckerRegistry.checker = nil
    }

    override func tearDown() async throws {
        TextSpellCheckerRegistry.checker = nil
        try await super.tearDown()
    }

    func testShortTextWithoutASpellCheckerIsUnknown() {
        XCTAssertNil(TextLanguageDetector.textLanguageCode(for: "hej"))
        XCTAssertNil(TextLanguageDetector.textLanguageCode(for: "   "))
        XCTAssertNil(TextLanguageDetector.textLanguageCode(for: ""))
    }

    func testShortTextUsesTheFirstLanguageThatSpellsItCorrectly() {
        TextSpellCheckerRegistry.checker = StubTextSpellChecker(
            languages: ["en", "sv"],
            reports: [
                SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey"]),
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: [], guesses: [])
            ]
        )
        XCTAssertEqual(TextLanguageDetector.textLanguageCode(for: "hej"), "sv")
    }

    func testMisspelledInEveryPreferredLanguageIsUnknown() {
        TextSpellCheckerRegistry.checker = StubTextSpellChecker(
            languages: ["en", "sv"],
            reports: [
                SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey"]),
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: true, completions: [], guesses: [])
            ]
        )
        XCTAssertNil(TextLanguageDetector.textLanguageCode(for: "hej"))
    }

    func testUncheckedDictionaryDoesNotCountAsCorrect() {
        let reports = [
            SpellLanguageAssessment(language: "sv", checked: false, misspelled: false, completions: [], guesses: [])
        ]
        XCTAssertTrue(TextLanguageDetector.isMisspelledInAllPreferred(reports))
        XCTAssertTrue(TextLanguageDetector.isMisspelledInAllPreferred([]))
        XCTAssertFalse(TextLanguageDetector.isMisspelledInAllPreferred([
            SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: []),
            SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: [], guesses: [])
        ]))
        XCTAssertTrue(TextLanguageDetector.isMisspelledInAllPreferred([
            SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: []),
            SpellLanguageAssessment(language: "sv", checked: true, misspelled: true, completions: [], guesses: [])
        ]))
    }

    func testSuggestionsComeFromTheCorrectLanguageBeforeTheFirstPreferred() {
        let reports = [
            SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey", "he"]),
            SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: ["hejda", "hej"], guesses: ["hejsan"])
        ]
        XCTAssertEqual(TextLanguageDetector.suggestions(for: "hej", assessments: reports), ["hejda"])
    }

    func testSuggestionsFallBackToTheFirstPreferredLanguage() {
        let reports = [
            SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey"]),
            SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: [], guesses: [])
        ]
        XCTAssertEqual(TextLanguageDetector.bestFittingLanguage(for: "hej", in: reports), "sv")
        XCTAssertEqual(TextLanguageDetector.suggestions(for: "hej", assessments: reports), ["hey"])
    }

    func testMisspelledWordUsesTheLanguageWithPrefixCompletions() {
        let reports = [
            SpellLanguageAssessment(language: "sv", checked: true, misspelled: true, completions: [], guesses: ["svara"]),
            SpellLanguageAssessment(
                language: "en",
                checked: true,
                misspelled: true,
                completions: ["complete", "complex", "complement", "completion", "completely"],
                guesses: []
            )
        ]
        XCTAssertEqual(
            TextLanguageDetector.suggestions(for: "comple", assessments: reports),
            ["complete", "complex", "complement", "completion"]
        )
    }

    func testSuggestionsDropTheSameWordAndDuplicates() {
        let reports = [
            SpellLanguageAssessment(
                language: "en",
                checked: true,
                misspelled: true,
                completions: ["Comple", "complete", "COMPLETE", "complex"],
                guesses: ["ignored"]
            )
        ]
        XCTAssertEqual(TextLanguageDetector.suggestions(for: "comple", assessments: reports), ["complete", "complex"])
    }

    func testAssignTextLanguageRemovesAnUnknownValue() {
        var environment = [Constants.envVarTextLanguage: "fr"]
        TextLanguageDetector.assignTextLanguage(of: "hej", to: &environment)
        XCTAssertNil(environment[Constants.envVarTextLanguage])

        TextSpellCheckerRegistry.checker = StubTextSpellChecker(
            languages: ["sv"],
            reports: [
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: [], guesses: [])
            ]
        )
        TextLanguageDetector.assignTextLanguage(of: "hej", to: &environment)
        XCTAssertEqual(environment[Constants.envVarTextLanguage], "sv")
    }

    func testSingleWordAndShortPhrasePreferSpellCheck() {
        XCTAssertTrue(TextLanguageDetector.prefersSpellCheck(for: "hej"))
        XCTAssertTrue(TextLanguageDetector.prefersSpellCheck(for: "hello world"))
        XCTAssertFalse(TextLanguageDetector.prefersSpellCheck(for: "this is english"))
        XCTAssertFalse(TextLanguageDetector.prefersSpellCheck(for: String(repeating: "字", count: 40)))
    }

    func testLongEnglishTextIsRecognizedAsEnglish() {
        let text = "The quick brown fox jumps over the lazy dog near the river after breakfast today."
        XCTAssertEqual(TextLanguageDetector.textLanguageCode(for: text), "en")
    }

    func testLongSwedishTextIsRecognizedAsSwedish() {
        let text = "Jag bor i Sverige och jag talar svenska varje dag med min familj hemma i köket."
        XCTAssertEqual(TextLanguageDetector.textLanguageCode(for: text), "sv")
    }

    func testLanguageAvailabilityMatchesPrimarySubtags() {
        let available: Set<String> = ["en_US", "sv", "zh-Hans"]
        XCTAssertTrue(SystemTextSpellChecker.isAvailable("en", available: available))
        XCTAssertTrue(SystemTextSpellChecker.isAvailable("en_GB", available: available))
        XCTAssertTrue(SystemTextSpellChecker.isAvailable("sv", available: available))
        XCTAssertTrue(SystemTextSpellChecker.isAvailable("zh_Hans", available: available))
        XCTAssertFalse(SystemTextSpellChecker.isAvailable("fr", available: available))
        XCTAssertFalse(SystemTextSpellChecker.isAvailable("en", available: []))
    }

    func testDictionaryHitRequiresARealCheck() {
        XCTAssertFalse(SystemTextSpellChecker.countsAsDictionaryHit(wordCount: 0, misspelled: false, hasCompletions: false, flagsUnknownWords: true))
        XCTAssertFalse(SystemTextSpellChecker.countsAsDictionaryHit(wordCount: 1, misspelled: false, hasCompletions: false, flagsUnknownWords: false))
        XCTAssertTrue(SystemTextSpellChecker.countsAsDictionaryHit(wordCount: 1, misspelled: false, hasCompletions: false, flagsUnknownWords: true))
        XCTAssertTrue(SystemTextSpellChecker.countsAsDictionaryHit(wordCount: 1, misspelled: true, hasCompletions: false, flagsUnknownWords: false))
        XCTAssertTrue(SystemTextSpellChecker.countsAsDictionaryHit(wordCount: 1, misspelled: false, hasCompletions: true, flagsUnknownWords: false))
    }

    func testLiveSpellCheckerKeepsEnglishTyposAndAcceptsHello() {
        TextSpellCheckerRegistry.checker = SystemTextSpellChecker.shared
        let typo = SystemTextSpellChecker.shared.assessments(for: "recieve")
        XCTAssertTrue(TextLanguageDetector.isMisspelledInAllPreferred(typo))
        XCTAssertFalse(TextLanguageDetector.suggestions(for: "recieve", assessments: typo).isEmpty)

        let hello = SystemTextSpellChecker.shared.assessments(for: "hello")
        XCTAssertFalse(TextLanguageDetector.isMisspelledInAllPreferred(hello))
        XCTAssertEqual(
            TextLanguageDetector.textLanguageCode(for: "hello"),
            hello.first { $0.checked && !$0.misspelled }?.language
        )

        let hej = SystemTextSpellChecker.shared.assessments(for: "hej")
        if let english = hej.first(where: { $0.language == "en" || $0.language.hasPrefix("en_") || $0.language.hasPrefix("en-") }),
           let swedish = hej.first(where: { $0.language == "sv" || $0.language.hasPrefix("sv_") || $0.language.hasPrefix("sv-") }) {
            XCTAssertTrue(english.checked && english.misspelled)
            XCTAssertTrue(swedish.checked && !swedish.misspelled)
            XCTAssertFalse(TextLanguageDetector.isMisspelledInAllPreferred(hej))
        }
    }

    func testScriptActionPublishesDetectedTextLanguageWithoutReplacingUILanguage() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("text_lang_\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try """
        #!/bin/sh
        printf '%s|%s|%s' "$OPENCLIP_LANGUAGE" "${OPENCLIP_TEXT_LANGUAGE-absent}" "$OPENCLIP_LOCALE"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let action = ScriptAction(id: "test.textlang", title: "Lang", icon: .symbol("terminal"), scriptURL: script)
        let context = ActionContext(
            selection: SelectionContext(
                text: "hej",
                sourceApp: AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")
            )
        )

        TextSpellCheckerRegistry.checker = StubTextSpellChecker(
            languages: ["sv"],
            reports: [
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: [], guesses: [])
            ]
        )
        guard case .text(let detected) = try await action.perform(context) else {
            return XCTFail("Expected text")
        }
        let parts = detected.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(parts.count, 3)
        guard parts.count == 3 else { return }
        XCTAssertFalse(parts[0].isEmpty, "OPENCLIP_LANGUAGE stays the UI language")
        XCTAssertEqual(parts[1], "sv")
        XCTAssertFalse(parts[2].isEmpty)

        TextSpellCheckerRegistry.checker = StubTextSpellChecker(
            languages: ["en", "sv"],
            reports: [
                SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: []),
                SpellLanguageAssessment(language: "sv", checked: true, misspelled: true, completions: [], guesses: [])
            ]
        )
        guard case .text(let unknown) = try await action.perform(context) else {
            return XCTFail("Expected text")
        }
        let unknownParts = unknown.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(unknownParts.count, 3)
        guard unknownParts.count == 3 else { return }
        XCTAssertEqual(unknownParts[1], "absent")
        XCTAssertEqual(unknownParts[0], parts[0])
    }
}
