import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class CompletionSettingsTests: XCTestCase {
    func testCompletionSettingDefaultsAreInTheCatalog() {
        let store = MemorySettingsStore()
        XCTAssertFalse(store.get(.completionCopyToClipboard))
        XCTAssertTrue(store.get(.completionOnlyMisspelled))
        XCTAssertEqual(store.get(.completionDisplayMode), CompletionDisplayMode.inline.rawValue)
        XCTAssertEqual(CompletionDisplayMode(rawValue: store.get(.completionDisplayMode)), .inline)

        XCTAssertTrue(CompletionDisplayMode.inline.opensWithSuggestionsVisible)
        XCTAssertFalse(CompletionDisplayMode.contextual.opensWithSuggestionsVisible)
        XCTAssertTrue(CompletionDisplayMode.inline.showsInlineChevron)
        XCTAssertFalse(CompletionDisplayMode.contextual.showsInlineChevron)
        XCTAssertFalse(CompletionDisplayMode.inline.showsContextualButton(hasSuggestions: true, suggestionsExpanded: false))
        XCTAssertTrue(CompletionDisplayMode.contextual.showsContextualButton(hasSuggestions: true, suggestionsExpanded: false))
        XCTAssertFalse(CompletionDisplayMode.contextual.showsContextualButton(hasSuggestions: false, suggestionsExpanded: false))
        XCTAssertFalse(CompletionDisplayMode.contextual.showsContextualButton(hasSuggestions: true, suggestionsExpanded: true))

        let names = Set(SettingsCatalog.coreKeys.map(\.name))
        XCTAssertTrue(names.contains(SettingKey.completionOnlyMisspelled.name))
        XCTAssertTrue(names.contains(SettingKey.completionDisplayMode.name))
    }

    func testOnlyMisspelledHidesAWordAcceptedByAnySpellingLanguage() {
        let store = MemorySettingsStore()
        let action = CompletionAction(
            settingsStore: store,
            spellChecker: StubTextSpellChecker(
                languages: ["en", "sv"],
                reports: [
                    SpellLanguageAssessment(language: "en", checked: true, misspelled: true, completions: [], guesses: ["hey", "he"]),
                    SpellLanguageAssessment(language: "sv", checked: true, misspelled: false, completions: ["hejda"], guesses: [])
                ]
            )
        )
        let context = ActionContext(
            selection: SelectionContext(
                text: "hej",
                sourceApp: AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")
            )
        )

        XCTAssertFalse(action.isEnabled(for: context))
        store.set(.completionOnlyMisspelled, value: false)
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertEqual(action.fetchCompletions(for: "hej"), ["hejda"])
    }

    func testOnlyMisspelledShowsAWordRejectedByEverySpellingLanguage() {
        let store = MemorySettingsStore()
        XCTAssertTrue(store.get(.completionOnlyMisspelled))
        let action = CompletionAction(
            settingsStore: store,
            spellChecker: StubTextSpellChecker(
                languages: ["en", "sv"],
                reports: [
                    SpellLanguageAssessment(
                        language: "en",
                        checked: true,
                        misspelled: true,
                        completions: ["complete", "complex"],
                        guesses: []
                    ),
                    SpellLanguageAssessment(language: "sv", checked: true, misspelled: true, completions: [], guesses: [])
                ]
            )
        )
        let context = ActionContext(
            selection: SelectionContext(
                text: "comple",
                sourceApp: AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")
            )
        )
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertEqual(action.fetchCompletions(for: "comple"), ["complete", "complex"])
    }

    func testMissingDictionaryDoesNotHideSuggestions() {
        let store = MemorySettingsStore()
        let action = CompletionAction(
            settingsStore: store,
            spellChecker: StubTextSpellChecker(
                languages: ["sv"],
                reports: [
                    SpellLanguageAssessment(language: "sv", checked: false, misspelled: false, completions: ["svar"], guesses: [])
                ]
            )
        )
        let context = ActionContext(
            selection: SelectionContext(
                text: "sva",
                sourceApp: AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")
            )
        )
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertEqual(action.fetchCompletions(for: "sva"), ["svar"])
    }
}
