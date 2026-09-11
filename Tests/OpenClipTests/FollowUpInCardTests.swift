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

    /// The card is content-sized, so a refinement streaming in would re-measure it on every chunk
    /// and make it jump. Its exact size is frozen for the whole refinement — and kept afterwards,
    /// like a hand-resized card — so a longer or shorter answer scrolls instead of resizing.
    func testTheCardKeepsItsExactSizeWhileARefinementStreams() async {
        let controller = makeController()
        defer { controller.hide() }
        let ring = 2 * PopupMetrics.popupShadowInset
        controller.panel?.setFrame(NSRect(x: 100, y: 100, width: 320 + ring, height: 260 + ring), display: false)
        XCTAssertFalse(controller.modeStore.isSurfaceUserSized, "content-sized before the follow-up")
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("make it much longer and more detailed")
        await fulfillment(of: [provider.started], timeout: 2)

        XCTAssertTrue(controller.modeStore.isSurfaceUserSized, "the size is pinned the moment the refinement starts")
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 320, height: 260))

        provider.continuation?.yield(String(repeating: "A much longer answer that would otherwise widen and grow the card. ", count: 12))
        await settle()
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 320, height: 260), "chunks do not change it")
        XCTAssertTrue(controller.modeStore.isSurfaceUserSized)

        provider.continuation?.finish()
        _ = await controller.activeStreamingTask?.value
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 320, height: 260), "nor does settling")
        XCTAssertTrue(controller.modeStore.isSurfaceUserSized)
    }

    /// A card the user already resized keeps that size; a panel too small to be a card (the
    /// default test panel) is ignored rather than pinned to nonsense.
    func testFreezingRespectsAUserResizeAndIgnoresATinyPanel() async {
        let controller = makeController()
        defer { controller.hide() }
        let provider = HeldProvider()
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        controller.runFollowUp("shorter")
        await fulfillment(of: [provider.started], timeout: 2)
        XCTAssertFalse(controller.modeStore.isSurfaceUserSized, "the 200×50 test panel is not a card size")
        provider.continuation?.finish()
        _ = await controller.activeStreamingTask?.value

        controller.modeStore.resultCardSize = CGSize(width: 400, height: 300)
        controller.modeStore.isSurfaceUserSized = true
        let second = HeldProvider()
        AIServiceManager.shared.providerOverride = second
        controller.runFollowUp("longer")
        await fulfillment(of: [second.started], timeout: 2)
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 400, height: 300), "a hand-resized card is left alone")
        second.continuation?.finish()
        _ = await controller.activeStreamingTask?.value
    }

    func testEscapeMeaningDependsOnWhetherAFollowUpIsInFlight() {
        XCTAssertTrue(ResultCardView.escapeCancelsFollowUp(isStreaming: true, canCancel: true))
        XCTAssertFalse(ResultCardView.escapeCancelsFollowUp(isStreaming: false, canCancel: true), "a settled card dismisses")
        XCTAssertFalse(ResultCardView.escapeCancelsFollowUp(isStreaming: true, canCancel: false), "a host without a cancel dismisses")
    }
}
