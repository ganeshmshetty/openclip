import XCTest
import AppKit
import Core
@testable import OpenClip

/// A follow-up refines the result card in place: the popup never hides, no loading toast shows,
/// the previous answer stays on screen (dimmed, `isRefining`) until the first chunk, the new
/// answer streams into the same card and settles with the diff against the text it ran on. Esc
/// cancels and keeps the previous answer; a failure restores it under an error toast; leaving
/// the card drops the stream.
@MainActor
final class FollowUpInCardTests: XCTestCase {

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

    /// A provider whose stream the test feeds by hand, so the card can be inspected mid-flight.
    @MainActor
    private final class HeldProvider: AIProvider {
        var type: AIProviderType { .cloud }
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        var lastText: String?
        var lastPrompt: String?
        let started = XCTestExpectation(description: "stream started")
        func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
            lastPrompt = prompt
            lastText = text
            return AsyncThrowingStream { continuation in
                self.continuation = continuation
                self.started.fulfill()
            }
        }
    }

    private func makeController() -> PopupWindowController {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: pasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel
        controller.startTestSession(for: selection("the original selection"))
        controller.showResultCard(text: "A long first answer", isError: false, title: "Rewrite", session: controller.aiSessionID)
        return controller
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testFollowUpStaysInTheCardAndStreamsInPlace() async {
        let controller = makeController()
        defer { controller.hide() }
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("make it shorter")
        await fulfillment(of: [provider.started], timeout: 2)

        XCTAssertEqual(controller.modeStore.mode, .content, "the card never leaves the screen")
        XCTAssertFalse(controller.toastController.isLoading, "no loading toast — the spinner is in the card")
        XCTAssertEqual(controller.modeStore.resultCard?.text, "A long first answer", "the previous answer stays visible")
        XCTAssertEqual(controller.modeStore.resultCard?.isRefining, true)
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, true)
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Make it shorter", "the header already names the follow-up")
        XCTAssertTrue(controller.modeStore.isProcessingAI)
        XCTAssertEqual(provider.lastText, "A long first answer")
        XCTAssertEqual(provider.lastPrompt, "make it shorter")

        provider.continuation?.yield("Shorter")
        await settle()
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Shorter")
        XCTAssertEqual(controller.modeStore.resultCard?.isRefining, false, "the first chunk lifts the dimming")
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, true)

        provider.continuation?.yield(" answer")
        provider.continuation?.finish()
        _ = await controller.activeStreamingTask?.value
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Shorter answer")
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, false)
        XCTAssertEqual(controller.modeStore.resultCard?.original, "A long first answer", "the diff compares against the text the follow-up ran on")
        XCTAssertFalse(controller.modeStore.isProcessingAI)
    }

    func testEscapeCancelsAndKeepsThePreviousAnswer() async {
        let controller = makeController()
        defer { controller.hide() }
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("make it shorter")
        await fulfillment(of: [provider.started], timeout: 2)
        controller.cancelFollowUp()
        await settle()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "A long first answer")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Rewrite", "the previous card is back as it was")
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, false)
        XCTAssertFalse(controller.modeStore.isProcessingAI)
        XCTAssertNil(controller.activeStreamingTask)

        provider.continuation?.yield("late chunk")
        await settle()
        XCTAssertEqual(controller.modeStore.resultCard?.text, "A long first answer", "a chunk after the cancel changes nothing")
    }

    func testAFailureRestoresThePreviousAnswerUnderAnErrorToast() async {
        let controller = makeController()
        defer { controller.hide() }
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("make it shorter")
        await fulfillment(of: [provider.started], timeout: 2)
        provider.continuation?.finish(throwing: AIError.httpStatus(500, "boom"))
        _ = await controller.activeStreamingTask?.value

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "A long first answer")
        XCTAssertEqual(controller.modeStore.resultCard?.isError, false, "the card is not turned into an error card")
        XCTAssertEqual(controller.toastController.currentFeedback?.style, .error)
    }

    func testLeavingTheCardDropsTheFollowUp() async {
        let controller = makeController()
        defer { controller.hide() }
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("make it shorter")
        await fulfillment(of: [provider.started], timeout: 2)
        controller.exitContent()
        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.activeStreamingTask)

        provider.continuation?.yield("late")
        provider.continuation?.finish()
        await settle()
        XCTAssertEqual(controller.modeStore.mode, .actions, "a late chunk must not re-open the card")
        XCTAssertNil(controller.modeStore.resultCard)
    }

    func testEscapeMeaningDependsOnWhetherAFollowUpIsInFlight() {
        XCTAssertTrue(ResultCardView.escapeCancelsFollowUp(isStreaming: true, canCancel: true))
        XCTAssertFalse(ResultCardView.escapeCancelsFollowUp(isStreaming: false, canCancel: true), "a settled card dismisses")
        XCTAssertFalse(ResultCardView.escapeCancelsFollowUp(isStreaming: true, canCancel: false), "a host without a cancel dismisses")
    }
}
