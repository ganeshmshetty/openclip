import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class DefineActionTests: XCTestCase {
    private let sampleDefinitions: [String: String] = [
        "serendipity": "the occurrence and development of events by chance in a happy or beneficial way.",
        "epiphany": "a moment of sudden and great revelation or realization."
    ]

    private func makeMockLookup() -> @Sendable (String) -> String? {
        let defs = sampleDefinitions
        return { word in
            defs[word.lowercased()]
        }
    }

    /// Isolated store so a developer's real `openInDictionaryApp` preference can't leak into these
    /// tests (which assert the default in-process lookup behaviour).
    private func makeStore() -> MemorySettingsStore {
        MemorySettingsStore()
    }

    @MainActor
    func testDefineActionSmartTrigger() async throws {
        let action = DefineAction(lookup: makeMockLookup(), settingsStore: makeStore())
        let app = AppIdentity(NSRunningApplication.current)
        
        // Single word with definition -> Enabled
        let wordContext = ActionContext(
            selection: SelectionContext(text: "serendipity", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: wordContext), "DefineAction should be enabled for single words with definitions")

        // Single word without definition -> Disabled
        let nonExistentContext = ActionContext(
            selection: SelectionContext(text: "nonexistentword", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: nonExistentContext), "DefineAction should be disabled for words without definitions")
        
        // Multi-word phrase -> Disabled
        let phraseContext = ActionContext(
            selection: SelectionContext(text: "quantum physics", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: phraseContext), "DefineAction should be disabled for multi-word phrases")
        
        // Math formula -> Disabled
        let mathContext = ActionContext(
            selection: SelectionContext(text: "12 + 4.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: mathContext), "DefineAction should be disabled for math expressions")
        
        // URL -> Disabled
        let urlContext = ActionContext(
            selection: SelectionContext(text: "https://apple.com", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: urlContext), "DefineAction should be disabled for URLs")

        // Empty-string definition -> Disabled (isEnabled must match perform, which returns .none)
        let emptyDefContext = ActionContext(
            selection: SelectionContext(text: "emptydef", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let emptyLookup: @Sendable (String) -> String? = { _ in "" }
        let emptyAction = DefineAction(lookup: emptyLookup, settingsStore: makeStore())
        XCTAssertFalse(emptyAction.isEnabled(for: emptyDefContext), "DefineAction should be disabled when lookup returns an empty definition")
        
        // Long paragraph (>40 chars or >3 words) -> Disabled
        let paragraphContext = ActionContext(
            selection: SelectionContext(text: "This is a very long text paragraph that exceeds the maximum length threshold.", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: paragraphContext), "DefineAction should be disabled for long paragraphs")
    }
    
    @MainActor
    func testDefineActionExecution() async throws {
        let action = DefineAction(lookup: makeMockLookup(), settingsStore: makeStore())
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "epiphany", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .text(let definition) = result {
            XCTAssertEqual(definition, "a moment of sudden and great revelation or realization.")
        } else {
            XCTFail("Expected text result for DefineAction, got \(result)")
        }
    }

    @MainActor
    func testDefineActionSecondaryClickReturnsText() async throws {
        let action = DefineAction(lookup: makeMockLookup(), settingsStore: makeStore())
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "epiphany", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: [],
            isSecondaryClick: true
        )

        let result = try await action.perform(context)
        if case .text(let definition) = result {
            XCTAssertEqual(definition, "a moment of sudden and great revelation or realization.")
        } else {
            XCTFail("Expected text result for secondary click on DefineAction, got \(result)")
        }
    }

    private func context(for text: String) -> ActionContext {
        let app = AppIdentity(NSRunningApplication.current)
        return ActionContext(
            selection: SelectionContext(text: text, sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
    }

    @MainActor
    func testDefineActionOpensInDictionaryAppWhenConfigured() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: DefineAction.actionID, optionID: "definitionDisplay"), value: "dictionary")
        let action = DefineAction(lookup: { _ in nil }, settingsStore: store)
        let context = self.context(for: "serendipity")

        XCTAssertTrue(action.isEnabled(for: context), "Dictionary mode enables a single word even without an in-process definition")

        let result = try await action.perform(context)
        guard case .openURL(let url) = result else {
            return XCTFail("Expected an openURL result in Dictionary mode, got \(result)")
        }
        XCTAssertEqual(url.scheme, "x-dictionary")
        XCTAssertTrue(url.absoluteString.contains("d:serendipity"))
    }

    @MainActor
    func testDefineActionPopoverModeReturnsShowDefinition() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: DefineAction.actionID, optionID: "definitionDisplay"), value: "popover")
        let action = DefineAction(lookup: { _ in nil }, settingsStore: store)
        let context = self.context(for: "serendipity")

        XCTAssertTrue(action.isEnabled(for: context), "Popover mode enables a single word without an in-process definition")

        let result = try await action.perform(context)
        guard case .showDefinition(let word) = result else {
            return XCTFail("Expected a showDefinition result in popover mode, got \(result)")
        }
        XCTAssertEqual(word, "serendipity")
    }

    @MainActor
    func testDefineActionDefaultsToCardMode() async throws {
        let action = DefineAction(lookup: makeMockLookup(), settingsStore: makeStore())
        XCTAssertEqual(action.display, .card)

        let result = try await action.perform(context(for: "epiphany"))
        guard case .text = result else {
            return XCTFail("Expected a text result in the default card mode, got \(result)")
        }
    }

    @MainActor
    func testLegacyDictionaryOptionMigratesToPicker() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: DefineAction.actionID, optionID: "openInDictionaryApp"), value: "true")

        DefineAction.migrateLegacyDisplayOptionIfNeeded(settingsStore: store)
        let action = DefineAction(lookup: { _ in nil }, settingsStore: store)
        XCTAssertEqual(action.display, .dictionary)

        guard case .openURL = try await action.perform(context(for: "serendipity")) else {
            return XCTFail("Expected legacy true to migrate to dictionary mode")
        }
    }

    @MainActor
    func testMigrationLeavesExplicitPickerUntouched() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.actionOption(actionID: DefineAction.actionID, optionID: "definitionDisplay"), value: "popover")
        store.set(SettingKey.actionOption(actionID: DefineAction.actionID, optionID: "openInDictionaryApp"), value: "true")

        DefineAction.migrateLegacyDisplayOptionIfNeeded(settingsStore: store)
        XCTAssertEqual(DefineAction(lookup: { _ in nil }, settingsStore: store).display, .popover)
    }
}
