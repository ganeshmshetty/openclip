import XCTest
import AppKit
import Core
@testable import OpenClip

/// The controller side of the palette's AI rows: ⏎ (`replace: true`) pastes the answer over the
/// selection — copies when the target can't paste or the app changed — and ⇧⏎ streams into the
/// result card; either way the instruction becomes a recent, and a saved one leaves the recents.
@MainActor
final class PaletteAIReplaceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func selection(_ text: String = "hello world", app: String = "com.test") -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: app, localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
    }

    private final class RecordingHandler: ActionResultHandler, @unchecked Sendable {
        var results: [ActionResult] = []
        func handle(_ result: ActionResult, in view: NSView?) async throws { results.append(result) }
        func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async { results.append(result) }
    }

    @MainActor
    private final class FixedProvider: AIProvider {
        var type: AIProviderType { .cloud }
        var lastText: String?
        var lastPrompt: String?
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

    private let store = MemorySettingsStore()

    private func makeController(handler: RecordingHandler) -> PopupWindowController {
        let controller = PopupWindowController(resultHandler: handler)
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel
        controller.promptHistory = AIPromptHistory(store: store)
        return controller
    }

    func testReturnPastesTheAnswerOverTheSelectionAndRemembersThePrompt() async {
        let handler = RecordingHandler()
        let controller = makeController(handler: handler)
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        controller.frontmostBundleIDProvider = { "com.test" }
        controller.startTestSession(for: selection("hello world"), pasteAvailable: true)
        defer { controller.hide() }

        controller.runAIPrompt("rewrite  to slovak", replace: true)
        XCTAssertTrue(controller.toastController.isLoading, "a Replacing… toast covers the wait")
        _ = await controller.activeStreamingTask?.value

        XCTAssertEqual(provider.lastText, "hello world")
        XCTAssertEqual(provider.lastPrompt, "rewrite to slovak")
        guard case .paste(let pasted)? = handler.results.last else {
            return XCTFail("the answer must be pasted over the selection, got \(handler.results)")
        }
        XCTAssertEqual(pasted, "ahoj svet")
        XCTAssertEqual(controller.modeStore.mode, .actions, "no card on the replace path")
        XCTAssertEqual(controller.toastController.currentFeedback?.message, "Replaced with AI result")
        XCTAssertEqual(store.get(.recentAIPrompts), ["rewrite to slovak"])
    }

    func testReplaceCopiesWhenTheTargetCannotPasteOrTheAppChanged() async {
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        let cannotPaste = RecordingHandler()
        let first = makeController(handler: cannotPaste)
        first.frontmostBundleIDProvider = { "com.test" }
        first.startTestSession(for: selection(), pasteAvailable: false)
        first.runAIPrompt("rewrite to slovak", replace: true)
        _ = await first.activeStreamingTask?.value
        first.hide()
        guard case .copy? = cannotPaste.results.last else { return XCTFail("cannot paste → copy") }

        let appChanged = RecordingHandler()
        let second = makeController(handler: appChanged)
        second.frontmostBundleIDProvider = { "com.somewhere.else" }
        second.startTestSession(for: selection(), pasteAvailable: true)
        second.runAIPrompt("rewrite to slovak", replace: true)
        _ = await second.activeStreamingTask?.value
        defer { second.hide() }
        guard case .copy? = appChanged.results.last else { return XCTFail("app changed → copy") }
        XCTAssertEqual(second.toastController.currentFeedback?.message, "Copied — the app changed")
    }

    func testShiftReturnStreamsIntoTheCardInstead() async {
        let handler = RecordingHandler()
        let controller = makeController(handler: handler)
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        controller.startTestSession(for: selection("hello world"), pasteAvailable: true)
        defer { controller.hide() }

        controller.runAIPrompt("rewrite to slovak", replace: false)
        _ = await controller.activeStreamingTask?.value

        XCTAssertTrue(handler.results.isEmpty, "nothing pasted on the card path")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "ahoj svet")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Rewrite to slovak")
        XCTAssertEqual(store.get(.recentAIPrompts), ["rewrite to slovak"], "remembered either way")
    }

    func testSavingAPromptTakesItOutOfTheRecents() async {
        let handler = RecordingHandler()
        let controller = makeController(handler: handler)
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        let presetsBefore = AIServiceManager.shared.presets
        defer { AIServiceManager.shared.presets = presetsBefore }
        controller.frontmostBundleIDProvider = { "com.test" }
        controller.startTestSession(for: selection(), pasteAvailable: true)
        defer { controller.hide() }

        controller.runAIPrompt("rewrite to slovak", replace: false)
        _ = await controller.activeStreamingTask?.value
        XCTAssertEqual(store.get(.recentAIPrompts), ["rewrite to slovak"])

        controller.saveAndRunAIPrompt("rewrite to slovak", replace: true)
        _ = await controller.activeStreamingTask?.value
        XCTAssertTrue(store.get(.recentAIPrompts).isEmpty, "a saved prompt is a preset now, not a recent")
        XCTAssertNotNil(AIServiceManager.shared.preset(matchingPrompt: "rewrite to slovak"))
        guard case .paste? = handler.results.last else { return XCTFail("Save with ⏎ still replaces in place") }
    }
}
