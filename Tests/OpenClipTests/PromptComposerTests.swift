import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The Ask AI bar entry and its prompt composer: the row rules, the recent-prompt history, the
/// action's chrome contract (bar-only, not searchable/groupable/bindable), and the composer
/// driven end-to-end (typed instruction + ⌘1 / Return / ⇧Return, recents by ⌘-digit).
@MainActor
final class PromptComposerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    // MARK: - Rows

    func testBlankQueryListsRecentsMostRecentFirst() {
        let rows = PromptComposerModel.rows(query: "", recents: ["make it friendly", "rewrite to slovak"])
        XCTAssertEqual(rows, [.recent("make it friendly"), .recent("rewrite to slovak")])
    }

    func testTypedQueryComesFirstFollowedByMatchingRecents() {
        let rows = PromptComposerModel.rows(query: "  slo  ", recents: ["make it friendly", "rewrite to slovak"])
        XCTAssertEqual(rows, [.ask("slo"), .recent("rewrite to slovak")])
    }

    func testQueryEqualToARecentDoesNotDuplicateIt() {
        let rows = PromptComposerModel.rows(query: "Rewrite To Slovak", recents: ["rewrite to slovak"])
        XCTAssertEqual(rows, [.recent("rewrite to slovak")], "the recent row already runs exactly that prompt")
    }

    func testNothingTypedAndNoRecentsGivesNoRows() {
        XCTAssertTrue(PromptComposerModel.rows(query: " \n", recents: []).isEmpty)
    }

    // MARK: - History

    func testRecordingMovesToFrontDeduplicatesAndCaps() {
        var list: [String] = []
        for i in 1...10 { list = AIPromptHistory.recording("prompt \(i)", in: list) }
        XCTAssertEqual(list.count, AIPromptHistory.capacity)
        XCTAssertEqual(list.first, "prompt 10")
        XCTAssertFalse(list.contains("prompt 1"), "the oldest fall off the end")
        list = AIPromptHistory.recording("  Prompt   4 ", in: list)
        XCTAssertEqual(list.first, "Prompt 4", "re-running moves it to the front, collapsed")
        XCTAssertEqual(list.filter { $0.lowercased() == "prompt 4" }.count, 1)
        XCTAssertEqual(AIPromptHistory.recording("   ", in: list), list, "a blank prompt changes nothing")
    }

    func testHistoryPersistsThroughTheSettingsStore() {
        let store = MemorySettingsStore()
        let history = AIPromptHistory(store: store)
        history.record("rewrite to slovak")
        history.record("make it friendly")
        XCTAssertEqual(store.get(.recentAIPrompts), ["make it friendly", "rewrite to slovak"])
        XCTAssertEqual(AIPromptHistory(store: store).prompts, ["make it friendly", "rewrite to slovak"], "a fresh instance reads it back")
        history.remove("Rewrite to slovak")
        XCTAssertEqual(store.get(.recentAIPrompts), ["make it friendly"])
    }

    // MARK: - Ask AI action contract

    private func context(text: String = "hello world") -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    func testAskAIIsABarOnlySurface() {
        let action = AskAIAction()
        XCTAssertTrue(action.chrome.composesPrompt)
        XCTAssertFalse(action.chrome.launchesAI)
        XCTAssertFalse(ActionIdentity.isBindable(action), "nothing to run from a hotkey")
        XCTAssertFalse(ActionIdentity.isEligibleForGrouping(action))
        ActionRegistry.shared.register(action: action)
        ActionRegistry.shared.register(action: MockAction(id: "mock.plain", shouldBeEnabled: true))
        let searchable = ActionRegistry.shared.searchCatalog(for: context()).map(\.id)
        XCTAssertFalse(searchable.contains("builtin.askAI"), "the composer is not a palette entry")
        XCTAssertTrue(searchable.contains("mock.plain"))
    }

    func testAskAINeedsTextToAskAbout() {
        XCTAssertFalse(AskAIAction().isEnabled(for: context(text: "")))
    }

    func testComposesPromptRoundTripsThroughCodable() throws {
        let chrome = ActionChrome(composesPrompt: true)
        let data = try JSONEncoder().encode(chrome)
        XCTAssertTrue(try JSONDecoder().decode(ActionChrome.self, from: data).composesPrompt)
        // Older payloads without the key decode to false.
        let legacy = try JSONEncoder().encode(ActionChrome())
        XCTAssertFalse(try JSONDecoder().decode(ActionChrome.self, from: legacy).composesPrompt)
    }

    // MARK: - Composer wiring

    private final class Recorder {
        var events: [String] = []
    }

    private func driveComposer(recents: [String], type text: String?, press key: (NSWindow) throws -> Void, recorder: Recorder) throws {
        let view = PromptComposerView(
            context: context(),
            recents: recents,
            maxSize: nil,
            onRun: { recorder.events.append("run:\($0)") },
            onSave: { recorder.events.append("save:\($0)") },
            onExit: { recorder.events.append("exit") },
            aiEnabled: true
        )
        .environment(\.colorScheme, .light)
        .environment(\.popupEffectiveTheme, "light")

        let host = NSHostingView(rootView: AnyView(view))
        host.layoutSubtreeIfNeeded()
        let panel = PopupPanel()
        panel.allowsKey = true
        panel.contentView = host
        panel.setFrame(NSRect(x: 300, y: 300, width: 360, height: 320), display: true)
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
        try key(panel)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private static func findTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }

    private func keyEvent(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags, in panel: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    func testCommandOneRunsTheTypedInstruction() throws {
        let recorder = Recorder()
        try driveComposer(recents: ["make it friendly"], type: "rewrite  to slovak", press: { panel in
            XCTAssertTrue(panel.performKeyEquivalent(with: try self.keyEvent("1", keyCode: 18, flags: [.command], in: panel)))
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["run:rewrite to slovak"])
    }

    func testCommandDigitRunsARecentWithNothingTyped() throws {
        let recorder = Recorder()
        try driveComposer(recents: ["make it friendly", "rewrite to slovak"], type: nil, press: { panel in
            XCTAssertTrue(panel.performKeyEquivalent(with: try self.keyEvent("2", keyCode: 19, flags: [.command], in: panel)))
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["run:rewrite to slovak"])
    }

    func testReturnRunsAndShiftReturnSaves() throws {
        let run = Recorder()
        try driveComposer(recents: [], type: "make it friendly", press: { panel in
            panel.sendEvent(try self.keyEvent("\r", keyCode: 36, flags: [], in: panel))
        }, recorder: run)
        XCTAssertEqual(run.events, ["run:make it friendly"])

        let save = Recorder()
        try driveComposer(recents: [], type: "make it friendly", press: { panel in
            panel.sendEvent(try self.keyEvent("\r", keyCode: 36, flags: [.shift], in: panel))
        }, recorder: save)
        XCTAssertEqual(save.events, ["save:make it friendly"])
    }

    func testEscapeExitsToTheBar() throws {
        let recorder = Recorder()
        try driveComposer(recents: [], type: nil, press: { panel in
            panel.sendEvent(try self.keyEvent("\u{1B}", keyCode: 53, flags: [], in: panel))
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["exit"])
    }
}
