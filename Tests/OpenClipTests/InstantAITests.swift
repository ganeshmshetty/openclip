import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The Instant AI hotkey: a one-line prompt on the selection whose answer replaces it in place.
/// Covers the prompt view's keys (⏎ replace, ⇧⏎ show, ↑ last prompt, Esc), the popup entry
/// (`showInstantPrompt` scopes search mode to the prompt), and the controller's replace flow
/// (paste when the target can paste and the source app is still frontmost, copy otherwise,
/// the instruction remembered for ↑).
@MainActor
final class InstantAITests: XCTestCase {

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

    // MARK: - Gate

    func testInstantPromptNeedsSubstantialText() {
        XCTAssertTrue(HotkeyManager.instantPromptAllowed(text: "hello world"))
        XCTAssertFalse(HotkeyManager.instantPromptAllowed(text: ""))
        XCTAssertFalse(HotkeyManager.instantPromptAllowed(text: "   "))
    }

    func testInstantParentComposesPromptsAndIsNotABarRow() {
        let parent = InstantAIAction()
        XCTAssertTrue(parent.chrome.composesPrompt)
        XCTAssertFalse(parent.chrome.launchesAI)
    }

    // MARK: - Prompt view

    private final class Recorder {
        var events: [String] = []
    }

    private func drivePrompt(lastPrompt: String?, type text: String?, press: (NSWindow) throws -> Void, recorder: Recorder) throws {
        let view = InstantPromptView(
            lastPrompt: lastPrompt,
            canPaste: true,
            onRun: { instruction, replace in recorder.events.append("\(replace ? "replace" : "show"):\(instruction)") },
            onExit: { recorder.events.append("exit") }
        )
        .environment(\.colorScheme, .light)
        .environment(\.popupEffectiveTheme, "light")

        let host = NSHostingView(rootView: AnyView(view))
        host.layoutSubtreeIfNeeded()
        let panel = PopupPanel()
        panel.allowsKey = true
        panel.contentView = host
        panel.setFrame(NSRect(x: 300, y: 300, width: 380, height: 120), display: true)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let field = try XCTUnwrap(Self.findTextField(in: host))
        panel.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        if let text {
            let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
            editor.insertText(text, replacementRange: NSRange(location: 0, length: 0))
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        try press(panel)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }

    private func key(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = [], in panel: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    func testReturnReplacesAndShiftReturnShowsTheCard() throws {
        let replace = Recorder()
        try drivePrompt(lastPrompt: nil, type: "rewrite  to slovak", press: { panel in
            panel.sendEvent(try self.key("\r", keyCode: 36, in: panel))
        }, recorder: replace)
        XCTAssertEqual(replace.events, ["replace:rewrite to slovak"])

        let show = Recorder()
        try drivePrompt(lastPrompt: nil, type: "rewrite to slovak", press: { panel in
            panel.sendEvent(try self.key("\r", keyCode: 36, flags: [.shift], in: panel))
        }, recorder: show)
        XCTAssertEqual(show.events, ["show:rewrite to slovak"])
    }

    func testUpArrowRecallsTheLastPrompt() throws {
        let recorder = Recorder()
        try drivePrompt(lastPrompt: "make it friendly", type: nil, press: { panel in
            // Arrow keys carry the NSUpArrowFunctionKey character, which is what SwiftUI keys on.
            panel.sendEvent(try self.key("\u{F700}", keyCode: 126, in: panel))
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            panel.sendEvent(try self.key("\r", keyCode: 36, in: panel))
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["replace:make it friendly"])
    }

    func testEmptyReturnDoesNothingAndEscapeExits() throws {
        let empty = Recorder()
        try drivePrompt(lastPrompt: nil, type: nil, press: { panel in
            panel.sendEvent(try self.key("\r", keyCode: 36, in: panel))
        }, recorder: empty)
        XCTAssertTrue(empty.events.isEmpty)

        let esc = Recorder()
        try drivePrompt(lastPrompt: nil, type: nil, press: { panel in
            panel.sendEvent(try self.key("\u{1B}", keyCode: 53, in: panel))
        }, recorder: esc)
        XCTAssertEqual(esc.events, ["exit"])
    }

    // MARK: - Controller

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

    private func makeController(handler: RecordingHandler) -> PopupWindowController {
        let controller = PopupWindowController(resultHandler: handler)
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel
        return controller
    }

    func testShowInstantPromptScopesSearchModeToThePrompt() {
        let controller = makeController(handler: RecordingHandler())
        defer { controller.hide() }
        controller.showInstantPrompt(for: selection(), pasteAvailable: true)
        XCTAssertEqual(controller.modeStore.mode, .search)
        XCTAssertTrue(controller.modeStore.scope?.parent.chrome.composesPrompt == true)
        XCTAssertTrue(controller.modeStore.scope?.children.isEmpty == true)
        XCTAssertEqual(controller.currentContext?.text, "hello world")
    }

    func testReplaceFlowPastesTheAnswerOverTheSelection() async {
        let handler = RecordingHandler()
        let controller = makeController(handler: handler)
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        controller.frontmostBundleIDProvider = { "com.test" }
        controller.startTestSession(for: selection("hello world"), pasteAvailable: true)
        defer { controller.hide() }

        controller.runInstantAI("rewrite to slovak", replace: true)
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
        XCTAssertEqual(DefaultSettingsStore.shared.get(.lastInstantAIPrompt), "rewrite to slovak")
    }

    func testReplaceFlowCopiesWhenTheTargetCannotPasteOrTheAppChanged() async {
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }

        let cannotPaste = RecordingHandler()
        let first = makeController(handler: cannotPaste)
        first.frontmostBundleIDProvider = { "com.test" }
        first.startTestSession(for: selection(), pasteAvailable: false)
        first.runInstantAI("rewrite to slovak", replace: true)
        _ = await first.activeStreamingTask?.value
        first.hide()
        guard case .copy? = cannotPaste.results.last else { return XCTFail("cannot paste → copy") }

        let appChanged = RecordingHandler()
        let second = makeController(handler: appChanged)
        second.frontmostBundleIDProvider = { "com.somewhere.else" }
        second.startTestSession(for: selection(), pasteAvailable: true)
        second.runInstantAI("rewrite to slovak", replace: true)
        _ = await second.activeStreamingTask?.value
        defer { second.hide() }
        guard case .copy? = appChanged.results.last else { return XCTFail("app changed → copy") }
        XCTAssertEqual(second.toastController.currentFeedback?.message, "Copied — the app changed")
    }

    func testShowPathStreamsIntoTheCardInstead() async {
        let handler = RecordingHandler()
        let controller = makeController(handler: handler)
        let provider = FixedProvider(reply: "ahoj svet")
        AIServiceManager.shared.providerOverride = provider
        defer { AIServiceManager.shared.providerOverride = nil }
        controller.startTestSession(for: selection("hello world"), pasteAvailable: true)
        defer { controller.hide() }

        controller.runInstantAI("rewrite to slovak", replace: false)
        _ = await controller.activeStreamingTask?.value

        XCTAssertTrue(handler.results.isEmpty, "nothing pasted on the review path")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "ahoj svet")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Rewrite to slovak")
    }
}
