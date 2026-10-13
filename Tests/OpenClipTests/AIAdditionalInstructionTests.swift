import XCTest
import AppKit
@testable import Core
@testable import OpenClip

/// Records every request an AI run makes and never answers, so a test can count requests and
/// inspect the exact prompt / selected text without the run going on to present a result card.
@MainActor
private final class RecordingAIProvider: AIProvider {
    var type: AIProviderType = .local
    private(set) var requests: [(prompt: String, text: String)] = []

    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        requests.append((prompt, text))
        return AsyncThrowingStream { _ in }
    }
}

/// The `{{additional_instruction}}` prompt variable: backward-compatible persistence, the pure
/// substitution rules, and the popup flow that asks for the instruction before a preset runs.
@MainActor
final class AIAdditionalInstructionTests: XCTestCase {
    private let placeholder = AIAdditionalInstruction.placeholder

    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
    }

    override func tearDown() async throws {
        AIServiceManager.shared.providerOverride = nil
        try await super.tearDown()
    }

    // MARK: - Persistence

    func testPresetSavedBeforeTheOptionExistedDecodesWithItOff() throws {
        let legacy = #"[{"id":"proofread","title":"Proofread","prompt":"Fix it.","isEnabled":true},"#
            + #"{"id":"custom_1a2b3c4d","title":"Mine","prompt":"Shorten.","isEnabled":false}]"#
        let presets = try JSONDecoder().decode([AIActionPreset].self, from: Data(legacy.utf8))

        XCTAssertEqual(presets.count, 2)
        XCTAssertEqual(presets[0], AIActionPreset(id: "proofread", title: "Proofread", prompt: "Fix it.", isEnabled: true))
        XCTAssertEqual(presets[1].prompt, "Shorten.")
        XCTAssertFalse(presets[1].isEnabled)
        XCTAssertFalse(presets.contains { $0.requestsAdditionalInstruction })
    }

    func testOptionRoundTripsThroughCodableInBothStates() throws {
        for isOn in [true, false] {
            let preset = AIActionPreset(
                id: "custom_x", title: "Rewrite", prompt: "Rewrite.\n\n\(placeholder)",
                isEnabled: true, requestsAdditionalInstruction: isOn
            )
            let data = try JSONEncoder().encode([preset])
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertTrue(json.contains("\"requestsAdditionalInstruction\":\(isOn)"))
            XCTAssertEqual(try JSONDecoder().decode([AIActionPreset].self, from: data), [preset])
        }
    }

    func testCustomDecodingKeepsThePerActionProviderAndModel() throws {
        let saved = #"[{"id":"custom_x","title":"Reply","prompt":"Reply.","isEnabled":true,"provider":"cloud","model":"gpt-5"}]"#
        let decoded = try XCTUnwrap(JSONDecoder().decode([AIActionPreset].self, from: Data(saved.utf8)).first)
        XCTAssertEqual(decoded.provider, "cloud")
        XCTAssertEqual(decoded.model, "gpt-5")
        XCTAssertFalse(decoded.requestsAdditionalInstruction)

        let preset = AIActionPreset(
            id: "custom_y", title: "Rewrite", prompt: "Rewrite.\n\n\(placeholder)",
            provider: "local", model: "qwen3", requestsAdditionalInstruction: true
        )
        let data = try JSONEncoder().encode([preset])
        XCTAssertEqual(try JSONDecoder().decode([AIActionPreset].self, from: data), [preset])
    }

    func testOptionDefaultsOffForBuiltInAndNewPresets() {
        XCTAssertFalse(AIServiceManager.defaultPresets.contains { $0.requestsAdditionalInstruction })
        XCTAssertFalse(AIServiceManager.makeCustomPreset(title: "T", prompt: "P").requestsAdditionalInstruction)
        XCTAssertTrue(AIServiceManager.makeCustomPreset(title: "T", prompt: "P", requestsAdditionalInstruction: true).requestsAdditionalInstruction)
    }

    func testNewActionDraftCarriesTheOption() throws {
        let store = MemorySettingsStore()
        let draft = AIPresetDraft(title: "Rewrite", prompt: "Rewrite.\n\n\(placeholder)", requestsAdditionalInstruction: true)
        let preset = try XCTUnwrap(draft.createPreset(
            bindings: ActionBindingStore(settingsStore: store),
            customizations: ActionCustomizationManager(settingsStore: store),
            saveShortcut: { _, _ in }, savePreset: { _ in }
        ))
        XCTAssertTrue(preset.requestsAdditionalInstruction)
        XCTAssertEqual(preset.prompt, "Rewrite.\n\n\(placeholder)")
    }

    // MARK: - Substitution

    func testSubstitutesAtTheBeginningMiddleAndEnd() {
        let instruction = "Use Austrian German spelling."
        XCTAssertEqual(
            AIAdditionalInstruction.resolve(prompt: "\(placeholder)\nReturn only the text.", with: instruction),
            "Use Austrian German spelling.\nReturn only the text."
        )
        XCTAssertEqual(
            AIAdditionalInstruction.resolve(prompt: "Correct the text.\n\nPay attention to:\n\(placeholder)\n\nReturn only the corrected text.", with: instruction),
            "Correct the text.\n\nPay attention to:\nUse Austrian German spelling.\n\nReturn only the corrected text."
        )
        XCTAssertEqual(
            AIAdditionalInstruction.resolve(prompt: "Rewrite professionally. \(placeholder)", with: instruction),
            "Rewrite professionally. Use Austrian German spelling."
        )
    }

    func testReplacesEveryOccurrence() {
        let resolved = AIAdditionalInstruction.resolve(prompt: "A: \(placeholder)\nB: \(placeholder)", with: "x")
        XCTAssertEqual(resolved, "A: x\nB: x")
        XCTAssertFalse(resolved.contains(placeholder))
    }

    func testInsertsUnicodeMultilineAndSpecialCharactersVerbatim() {
        let instruction = "  Österreichisch, bitte — „freundlich“ 😊\nZeile 2: $1 \\n & {{other}} \\(x)  \n"
        let resolved = AIAdditionalInstruction.resolve(prompt: "Task:\n\(placeholder)\nEnd.", with: instruction)
        XCTAssertEqual(resolved, "Task:\nÖsterreichisch, bitte — „freundlich“ 😊\nZeile 2: $1 \\n & {{other}} \\(x)\nEnd.")
    }

    func testLongInstructionIsKeptWhole() {
        let instruction = String(repeating: "Keep the tone friendly. ", count: 500).trimmingCharacters(in: .whitespaces)
        let resolved = AIAdditionalInstruction.resolve(prompt: "Rewrite.\n\(placeholder)", with: instruction)
        XCTAssertEqual(resolved, "Rewrite.\n\(instruction)")
    }

    func testMissingPlaceholderAppendsTheInstructionInsteadOfDroppingIt() {
        XCTAssertEqual(
            AIAdditionalInstruction.resolve(prompt: "Rewrite the text.\n", with: "Be brief."),
            "Rewrite the text.\n\nAdditional instruction:\nBe brief."
        )
        XCTAssertEqual(AIAdditionalInstruction.resolve(prompt: "", with: "Be brief."), "Be brief.")
    }

    func testBlankInstructionNeverLeavesAnUnresolvedPlaceholder() {
        XCTAssertEqual(AIAdditionalInstruction.resolve(prompt: "Rewrite.\n\n\(placeholder)", with: " \n "), "Rewrite.")
    }

    // MARK: - Editor rules

    func testEnablingAppendsThePlaceholderOnceAndDisablingRestoresThePrompt() {
        let prompt = "Rewrite the following text professionally.\nReturn only the final text."
        let enabled = AIAdditionalInstruction.insertingPlaceholder(into: prompt)
        XCTAssertEqual(enabled, "\(prompt)\n\n\(placeholder)")
        XCTAssertEqual(AIAdditionalInstruction.insertingPlaceholder(into: enabled), enabled, "An existing placeholder is never duplicated")
        XCTAssertEqual(AIAdditionalInstruction.removingPlaceholder(from: enabled), prompt)
        XCTAssertEqual(AIAdditionalInstruction.insertingPlaceholder(into: ""), placeholder)
    }

    func testEnablingKeepsAPlaceholderTheUserAlreadyPositioned() {
        let prompt = "Rewrite.\n\nAdditional requirements:\n\(placeholder)\n\nReturn only the text."
        XCTAssertEqual(AIAdditionalInstruction.insertingPlaceholder(into: prompt), prompt)
    }

    func testDisablingRemovesAPositionedPlaceholderAndOnlyItsWhitespace() {
        XCTAssertEqual(
            AIAdditionalInstruction.removingPlaceholder(from: "Rewrite.\n\nAdditional requirements:\n\(placeholder)\n\nReturn only the text."),
            "Rewrite.\n\nAdditional requirements:\n\nReturn only the text."
        )
        XCTAssertEqual(
            AIAdditionalInstruction.removingPlaceholder(from: "Intro.\n\n\(placeholder)\n\nOutro.\n\n\nKeep  spacing."),
            "Intro.\n\nOutro.\n\n\nKeep  spacing."
        )
        XCTAssertEqual(AIAdditionalInstruction.removingPlaceholder(from: "Use \(placeholder) carefully."), "Use carefully.")
        XCTAssertEqual(AIAdditionalInstruction.removingPlaceholder(from: "\(placeholder)\n\nRewrite."), "Rewrite.")
    }

    // MARK: - Prompt resolution per run

    func testPresetWithoutTheOptionRunsItsSavedPromptUnchanged() {
        let preset = AIActionPreset(id: "rewrite", title: "Rewrite", prompt: "Rewrite for clarity.")
        XCTAssertEqual(AIServiceManager.prompt(for: preset), "Rewrite for clarity.")
        XCTAssertEqual(AIServiceManager.prompt(for: preset, additionalInstruction: "ignored"), "Rewrite for clarity.")
    }

    func testStrayPlaceholderNeverReachesTheProviderWhileTheOptionIsOff() {
        let preset = AIActionPreset(id: "custom_x", title: "X", prompt: "Rewrite.\n\n\(placeholder)")
        XCTAssertEqual(AIServiceManager.prompt(for: preset), "Rewrite.")
    }

    func testResolvingNeverRewritesTheSavedPrompt() {
        let saved = "Correct the text.\n\(placeholder)"
        let preset = AIActionPreset(id: "custom_x", title: "X", prompt: saved, requestsAdditionalInstruction: true)
        XCTAssertEqual(AIServiceManager.prompt(for: preset, additionalInstruction: "First"), "Correct the text.\nFirst")
        XCTAssertEqual(AIServiceManager.prompt(for: preset, additionalInstruction: "Second"), "Correct the text.\nSecond")
        XCTAssertEqual(preset.prompt, saved)
    }

    func testRunButtonNeedsMoreThanWhitespace() {
        XCTAssertFalse(AdditionalInstructionCardView.canSubmit(""))
        XCTAssertFalse(AdditionalInstructionCardView.canSubmit(" \n\t "))
        XCTAssertTrue(AdditionalInstructionCardView.canSubmit(" x "))
    }

    // MARK: - Popup flow

    private func makeController(selection text: String = "Hallo Welt, wie geht's?") -> (PopupWindowController, RecordingAIProvider) {
        let provider = RecordingAIProvider()
        AIServiceManager.shared.providerOverride = provider
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        let context = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        return (controller, provider)
    }

    /// Lets the run's streaming task start (it resolves the provider and opens the stream).
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }

    private let promptWithVariable = "Correct the following text.\n\nPay particular attention to:\n{{additional_instruction}}\n\nReturn only the corrected text."

    func testPresetWithoutTheOptionRunsImmediatelyAsBefore() async {
        let (controller, provider) = makeController()
        controller.runSavedAIPreset(AIActionPreset(id: "proofread", title: "Proofread", prompt: "Fix spelling."))
        await settle()

        XCTAssertNotEqual(controller.modeStore.mode, .instruction)
        XCTAssertNil(controller.modeStore.instructionRequest)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.prompt, "Fix spelling.")
        XCTAssertEqual(provider.requests.first?.text, "Hallo Welt, wie geht's?")
        controller.hide()
    }

    func testPresetWithTheOptionAsksFirstAndSendsNothing() async {
        let (controller, provider) = makeController()
        let preset = AIActionPreset(id: "custom_x", title: "Correct", prompt: promptWithVariable, requestsAdditionalInstruction: true)
        controller.runSavedAIPreset(preset)
        await settle()

        XCTAssertEqual(controller.modeStore.mode, .instruction)
        XCTAssertEqual(controller.modeStore.instructionRequest?.preset, preset)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(controller.currentActionContext?.selection.text, "Hallo Welt, wie geht's?", "Asking must keep the selection the run will use")
        controller.hide()
    }

    func testCancellingSendsNothingAndLeavesTheClipboardAlone() async {
        let (controller, provider) = makeController()
        controller.runSavedAIPreset(AIActionPreset(id: "custom_x", title: "Correct", prompt: promptWithVariable, requestsAdditionalInstruction: true))
        let requestID = try? XCTUnwrap(controller.modeStore.instructionRequest?.id)
        let clipboardChangeCount = NSPasteboard.general.changeCount

        controller.cancelAdditionalInstruction()
        await settle()

        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.instructionRequest)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)

        // A submit arriving after the cancel (e.g. a late ⌘⏎) must not run the request.
        if let requestID {
            controller.submitAdditionalInstruction("Too late", requestID: requestID)
        }
        await settle()
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testSubmitRunsOnceWithTheResolvedPromptAndTheOriginalSelection() async throws {
        let (controller, provider) = makeController(selection: "Ich hab das gestern gemacht.")
        let preset = AIActionPreset(id: "custom_x", title: "Correct", prompt: promptWithVariable, requestsAdditionalInstruction: true)
        controller.runSavedAIPreset(preset)
        let requestID = try XCTUnwrap(controller.modeStore.instructionRequest?.id)

        controller.submitAdditionalInstruction("Use Austrian German spelling and keep the tone friendly.", requestID: requestID)
        controller.submitAdditionalInstruction("Use Austrian German spelling and keep the tone friendly.", requestID: requestID)
        await settle()

        XCTAssertEqual(provider.requests.count, 1, "A repeated submit must not start a second request")
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.prompt, "Correct the following text.\n\nPay particular attention to:\nUse Austrian German spelling and keep the tone friendly.\n\nReturn only the corrected text.")
        XCTAssertFalse(request.prompt.contains("{{"))
        XCTAssertEqual(request.text, "Ich hab das gestern gemacht.", "The selection travels separately and unchanged")
        XCTAssertFalse(request.prompt.contains("Ich hab das gestern gemacht."), "The selection must not be appended to the prompt as well")
        XCTAssertEqual(preset.prompt, promptWithVariable)
        controller.hide()
    }

    func testBlankOrStaleSubmitsAreIgnored() async throws {
        let (controller, provider) = makeController()
        let preset = AIActionPreset(id: "custom_x", title: "Correct", prompt: promptWithVariable, requestsAdditionalInstruction: true)
        controller.runSavedAIPreset(preset)
        let first = try XCTUnwrap(controller.modeStore.instructionRequest?.id)

        controller.submitAdditionalInstruction("   \n ", requestID: first)
        XCTAssertEqual(controller.modeStore.mode, .instruction, "A blank instruction keeps the prompt open")

        // Triggering the action again replaces the prompt; the old one can no longer submit.
        controller.runSavedAIPreset(preset)
        let second = try XCTUnwrap(controller.modeStore.instructionRequest?.id)
        XCTAssertNotEqual(first, second)
        controller.submitAdditionalInstruction("From the old prompt", requestID: first)
        await settle()
        XCTAssertTrue(provider.requests.isEmpty)

        controller.submitAdditionalInstruction("From the new prompt", requestID: second)
        await settle()
        XCTAssertEqual(provider.requests.map(\.prompt), [AIServiceManager.prompt(for: preset, additionalInstruction: "From the new prompt")])
        controller.hide()
    }

    func testRepeatingTheActionUsesEachRunsOwnInstruction() async throws {
        let (controller, provider) = makeController()
        let preset = AIActionPreset(id: "custom_x", title: "Correct", prompt: "Fix.\n\(placeholder)", requestsAdditionalInstruction: true)

        controller.runSavedAIPreset(preset)
        controller.submitAdditionalInstruction("formal", requestID: try XCTUnwrap(controller.modeStore.instructionRequest?.id))
        await settle()
        let context = SelectionContext(
            text: "Second selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        controller.runSavedAIPreset(preset)
        controller.submitAdditionalInstruction("casual", requestID: try XCTUnwrap(controller.modeStore.instructionRequest?.id))
        await settle()

        XCTAssertEqual(provider.requests.map(\.prompt), ["Fix.\nformal", "Fix.\ncasual"])
        XCTAssertEqual(provider.requests.map(\.text), ["Hallo Welt, wie geht's?", "Second selection"])
        XCTAssertEqual(preset.prompt, "Fix.\n\(placeholder)")
        controller.hide()
    }

    func testDismissingThePopupDropsThePendingRequest() async throws {
        let (controller, provider) = makeController()
        controller.runSavedAIPreset(AIActionPreset(id: "custom_x", title: "Correct", prompt: promptWithVariable, requestsAdditionalInstruction: true))
        let requestID = try XCTUnwrap(controller.modeStore.instructionRequest?.id)

        controller.hide()
        controller.submitAdditionalInstruction("After dismissal", requestID: requestID)
        await settle()

        XCTAssertNil(controller.modeStore.instructionRequest)
        XCTAssertTrue(provider.requests.isEmpty)
    }
}
