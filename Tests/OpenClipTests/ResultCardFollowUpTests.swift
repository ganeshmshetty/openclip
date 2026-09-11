import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The result card's follow-up field and the AI Tools "Ask…" entry: an instruction typed into
/// the card runs AI on the card's current text and re-streams the card (titled after the
/// instruction, diffed against the text it ran on); the ask card opens on the selection with
/// no result yet; an empty ⏎ keeps the card's paste/copy meaning.
@MainActor
final class ResultCardFollowUpTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func selection(_ text: String = "hello world") -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
    }

    // MARK: - Payload / entry

    func testPayloadIsAResultByDefault() {
        XCTAssertFalse(ResultCardPayload(text: "x", isError: false).awaitsInstruction)
    }

    func testAskEntryIsAnAISourcedActionThatPromptsForTheInstruction() {
        let ask = AskAIAction()
        XCTAssertTrue(ActionIdentity.isAIPreset(ask), "lists with the presets in AI Tools and the palette")
        XCTAssertTrue(ask is any InstructionPromptingAction)
        XCTAssertTrue(AIToolsAction().subActions(in: [ask, AIAction(presetID: "proofread", title: "Proofread")]).map(\.id).first == "ai.ask")
        XCTAssertFalse(ask.isEnabled(for: ActionContext(selection: selection(""))), "nothing to ask about")
    }

    // MARK: - Card field

    func testReturnDecisionTable() {
        typealias R = ResultCardView.FollowUpReturn
        XCTAssertEqual(ResultCardView.followUpReturn(text: " make it  shorter ", awaitsInstruction: false, isStreaming: false, canPaste: true, shift: false), R.followUp("make it  shorter"), "the raw text goes up; the controller collapses it")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "shorter", awaitsInstruction: true, isStreaming: false, canPaste: nil, shift: false), R.followUp("shorter"), "the first instruction on the ask card")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "shorter", awaitsInstruction: false, isStreaming: true, canPaste: true, shift: false), R.nothing, "wait for the answer to settle")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", awaitsInstruction: false, isStreaming: false, canPaste: true, shift: false), R.paste, "empty ⏎ keeps the card's meaning")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", awaitsInstruction: false, isStreaming: false, canPaste: false, shift: false), R.copy)
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", awaitsInstruction: false, isStreaming: false, canPaste: true, shift: true), R.copy, "⇧⏎ copies")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "  ", awaitsInstruction: true, isStreaming: false, canPaste: true, shift: false), R.nothing, "nothing to paste before the first answer")
    }

    /// The field is only there when a host can run a follow-up and the card is not an error.
    func testCardHostsTheFieldOnlyWhenAFollowUpCanRun() throws {
        XCTAssertNotNil(try hostedField(ResultCardPayload(text: "A result", isError: false, title: "Rewrite"), followUp: true))
        XCTAssertNil(try hostedField(ResultCardPayload(text: "A result", isError: false, title: "Rewrite"), followUp: false))
        XCTAssertNil(try hostedField(ResultCardPayload(text: "Boom", isError: true, title: "Rewrite"), followUp: true))
        XCTAssertNotNil(try hostedField(ResultCardPayload(text: "hello world", isError: false, title: "Ask AI", awaitsInstruction: true), followUp: true))
    }

    private func hostedField(_ payload: ResultCardPayload, followUp: Bool) throws -> NSTextField? {
        let view = ResultCardView(
            payload: payload,
            canPaste: true,
            onExit: {},
            onPaste: {},
            onCopy: {},
            onFollowUp: followUp ? { _ in } : nil
        )
        .environment(\.colorScheme, .light)
        .environment(\.popupEffectiveTheme, "light")
        let hosting = NSHostingView(rootView: AnyView(view))
        let panel = PopupPanel()
        panel.contentView = hosting
        panel.setFrame(NSRect(x: 300, y: 300, width: 400, height: 360), display: true)
        panel.orderFront(nil)
        defer { panel.orderOut(nil) }
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            if let field = PopupWindowController.findEditableTextField(in: hosting) { return field }
        }
        return nil
    }

    // MARK: - Controller

    @MainActor
    private final class RecordingProvider: AIProvider {
        var type: AIProviderType { .cloud }
        var lastPrompt: String?
        var lastText: String?
        let reply: String
        init(reply: String) { self.reply = reply }
        func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
            lastPrompt = prompt
            lastText = text
            let reply = self.reply
            return AsyncThrowingStream { continuation in
                continuation.yield(reply)
                continuation.finish()
            }
        }
    }

    private func makeController() -> PopupWindowController {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: pasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel
        return controller
    }

    func testFollowUpRunsOnTheCardTextAndDiffsAgainstIt() async {
        let controller = makeController()
        let provider = RecordingProvider(reply: "Shorter answer")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.startTestSession(for: selection("the original selection"))
        defer { controller.hide() }
        controller.showResultCard(text: "A long first answer", isError: false, title: "Rewrite", session: controller.aiSessionID)

        controller.runFollowUp("  make it   shorter ")
        _ = await controller.activeStreamingTask?.value

        XCTAssertEqual(provider.lastText, "A long first answer", "the follow-up runs on the card's text, not the selection")
        XCTAssertEqual(provider.lastPrompt, "make it shorter")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Shorter answer")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Make it shorter")
        XCTAssertEqual(controller.modeStore.resultCard?.original, "A long first answer", "the diff compares against what the instruction ran on")
        XCTAssertEqual(controller.modeStore.resultCard?.awaitsInstruction, false)
    }

    func testAskEntryOpensTheAskCardOnTheSelection() {
        let controller = makeController()
        ActionRegistry.shared.register(action: AskAIAction())
        controller.startTestSession(for: selection("hello world"))
        defer { controller.hide() }

        controller.runAISelection(actionID: "ai.ask")

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.awaitsInstruction, true)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "hello world")
        XCTAssertNil(controller.modeStore.resultCard?.icon, "sparkles header")
    }

    func testAPresetStillRunsItsPromptThroughTheSameRoute() async {
        let controller = makeController()
        let provider = RecordingProvider(reply: "Fixed")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        controller.startTestSession(for: selection("teh text"))
        defer { controller.hide() }

        controller.runAISelection(actionID: "ai.preset.proofread")
        _ = await controller.activeStreamingTask?.value

        XCTAssertEqual(provider.lastText, "teh text")
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Fixed")
        XCTAssertEqual(controller.modeStore.resultCard?.original, "teh text")
    }
}
