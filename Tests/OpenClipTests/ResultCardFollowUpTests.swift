import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The result card's follow-up field: an instruction typed into the card runs AI on the card's
/// current text and re-streams the card (titled after the instruction, diffed against the text
/// it ran on); an empty ⏎ keeps the card's paste/copy meaning.
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

    func testReturnDecisionTable() {
        typealias R = ResultCardView.FollowUpReturn
        XCTAssertEqual(ResultCardView.followUpReturn(text: " make it  shorter ", isStreaming: false, canPaste: true, shift: false), R.followUp("make it  shorter"), "the raw text goes up; the controller collapses it")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "shorter", isStreaming: true, canPaste: true, shift: false), R.nothing, "wait for the answer to settle")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", isStreaming: false, canPaste: true, shift: false), R.paste, "empty ⏎ keeps the card's meaning")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", isStreaming: true, canPaste: true, shift: false), R.nothing, "no paste of a half-written refinement")
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", isStreaming: false, canPaste: false, shift: false), R.copy)
        XCTAssertEqual(ResultCardView.followUpReturn(text: "", isStreaming: false, canPaste: true, shift: true), R.copy, "⇧⏎ copies")
    }

    func testCardWidthExpansionAndMaxLimit() {
        // When follow-up is shown, minimum width expands to 340
        XCTAssertEqual(ResultCardView.cardWidth(naturalTextWidth: 100, showsFollowUp: true, isUserSized: false, userWidth: nil), 340.0)
        // When follow-up is not shown, minimum width is PopupMetrics.aiCardMinWidth (220)
        XCTAssertEqual(ResultCardView.cardWidth(naturalTextWidth: 100, showsFollowUp: false, isUserSized: false, userWidth: nil), PopupMetrics.aiCardMinWidth)
        // Wide text is capped at max limit (400 for follow-up)
        XCTAssertEqual(ResultCardView.cardWidth(naturalTextWidth: 600, showsFollowUp: true, isUserSized: false, userWidth: nil), 400.0)
        // User sized width is respected
        XCTAssertEqual(ResultCardView.cardWidth(naturalTextWidth: 200, showsFollowUp: true, isUserSized: true, userWidth: 450), 450.0)
    }

    func testTypingCollapsesControls() {
        XCTAssertFalse(ResultCardView.isTyping(text: ""))
        XCTAssertFalse(ResultCardView.isTyping(text: "   \n\t "))
        XCTAssertTrue(ResultCardView.isTyping(text: "make it shorter"))
    }

    /// The field is only there when a host can run a follow-up and the card is not an error.
    func testCardHostsTheFieldOnlyWhenAFollowUpCanRun() throws {
        XCTAssertNotNil(try hostedField(ResultCardPayload(text: "A result", isError: false, title: "Rewrite"), followUp: true))
        XCTAssertNil(try hostedField(ResultCardPayload(text: "A result", isError: false, title: "Rewrite"), followUp: false))
        XCTAssertNil(try hostedField(ResultCardPayload(text: "Boom", isError: true, title: "Rewrite"), followUp: true))
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

    func testFollowUpRunsOnTheCardTextAndDiffsAgainstTheSelection() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: pasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel
        let provider = RecordingProvider(reply: "Shorter answer")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.startTestSession(for: selection("the original selection"))
        defer { controller.hide() }
        controller.showResultCard(text: "A long first answer", isError: false, title: "Rewrite", session: controller.aiSessionID)

        controller.runFollowUp("  make it   shorter ")
        _ = await controller.activeStreamingTask?.value

        XCTAssertEqual(provider.lastText, "A long first answer", "the follow-up runs on the card's text, not the selection")
        XCTAssertTrue(provider.lastPrompt?.hasPrefix("CURRENT TASK") == true, "the instruction leads the composite task")
        XCTAssertTrue(provider.lastPrompt?.contains("make it shorter") == true, "collapsed instruction")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Shorter answer")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Make it shorter")
        XCTAssertEqual(controller.modeStore.resultCard?.original, "the original selection", "the diff base is the selection, not the previous answer")
    }
}
