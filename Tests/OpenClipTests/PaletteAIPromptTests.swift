import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The search palette's AI fallback: a query that matches no action is offered as an AI
/// instruction — "Ask AI" runs it once, "Save as AI tool" keeps it as a custom preset and runs
/// it. Covers the pure rules (`PaletteAIPrompt`, the preset factory) and the palette wiring
/// (typing a non-matching query, then ⌘1 / ⌘2 / Return).
@MainActor
final class PaletteAIPromptTests: XCTestCase {

    // MARK: - Rows

    func testRowsAppearOnlyForANonBlankQueryWhileAIIsOn() {
        XCTAssertEqual(PaletteAIPrompt.rows(for: "rewrite to slovak", aiEnabled: true, results: .none), [.ask, .save])
        XCTAssertEqual(PaletteAIPrompt.rows(for: "x", aiEnabled: true, results: .none), [.ask, .save])
        XCTAssertTrue(PaletteAIPrompt.rows(for: "", aiEnabled: true, results: .none).isEmpty)
        XCTAssertTrue(PaletteAIPrompt.rows(for: "   \n", aiEnabled: true, results: .none).isEmpty, "whitespace is not a prompt")
        XCTAssertTrue(PaletteAIPrompt.rows(for: "rewrite to slovak", aiEnabled: false, results: .none).isEmpty,
                      "with AI off the empty state keeps its plain copy")
    }

    func testRowsFollowWhatMatched() {
        XCTAssertEqual(PaletteAIPrompt.rows(for: "slovak", aiEnabled: true, results: .onlyRecentPrompts), [.save],
                       "a recent already runs the query, so only Save is offered under it")
        XCTAssertTrue(PaletteAIPrompt.rows(for: "copy", aiEnabled: true, results: .actions).isEmpty,
                      "real matches leave no room for AI rows")
    }

    func testAskRowIsFirstSoCommandOneRunsIt() {
        XCTAssertEqual(PaletteAIPrompt.rows(for: "q", aiEnabled: true, results: .none).first, .ask)
    }

    func testHintNamesTheDeliveryTheTargetAllows() {
        XCTAssertTrue(PaletteAIPrompt.hint(canPaste: true).contains("replace"))
        XCTAssertTrue(PaletteAIPrompt.hint(canPaste: nil).contains("replace"), "unknown keeps the paste wording")
        XCTAssertTrue(PaletteAIPrompt.hint(canPaste: false).contains("copy"))
    }

    // MARK: - Instruction

    func testInstructionTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(PaletteAIPrompt.instruction(from: "  rewrite   to\tslovak \n"), "rewrite to slovak")
        XCTAssertEqual(PaletteAIPrompt.instruction(from: "plain"), "plain")
        XCTAssertEqual(PaletteAIPrompt.instruction(from: " \n "), "")
    }

    // MARK: - Tool title

    func testToolTitleCapitalisesTheFirstLetterOnly() {
        XCTAssertEqual(PaletteAIPrompt.toolTitle(for: "rewrite to slovak"), "Rewrite to slovak")
        XCTAssertEqual(PaletteAIPrompt.toolTitle(for: "  make it SHORTER "), "Make it SHORTER")
        XCTAssertEqual(PaletteAIPrompt.toolTitle(for: "über"), "Über")
        XCTAssertEqual(PaletteAIPrompt.toolTitle(for: ""), "")
    }

    func testToolTitleElidesLongPromptsAtAWordBoundary() {
        let prompt = "rewrite this paragraph in a friendly, casual tone for a newsletter audience"
        let title = PaletteAIPrompt.toolTitle(for: prompt)
        XCTAssertLessThanOrEqual(title.count, PaletteAIPrompt.maxToolTitleLength)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(title, "Rewrite this paragraph in a friendly,…")
        XCTAssertFalse(title.contains(" …"), "no dangling space before the ellipsis")
    }

    func testToolTitleFallsBackToAHardCutWhenThereIsNoUsableWordBoundary() {
        let prompt = String(repeating: "a", count: 60)
        let title = PaletteAIPrompt.toolTitle(for: prompt)
        XCTAssertEqual(title.count, PaletteAIPrompt.maxToolTitleLength)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testToolTitleKeepsAPromptAtTheLimitIntact() {
        let prompt = String(repeating: "b", count: PaletteAIPrompt.maxToolTitleLength)
        XCTAssertEqual(PaletteAIPrompt.toolTitle(for: prompt), "B" + String(repeating: "b", count: PaletteAIPrompt.maxToolTitleLength - 1))
    }

    func testRowTitlesQuoteTheQueryForAskOnly() {
        XCTAssertTrue(PaletteAIPrompt.rowTitle(.ask, query: "  rewrite  to slovak").contains("“rewrite to slovak”"))
        XCTAssertFalse(PaletteAIPrompt.rowTitle(.save, query: "rewrite to slovak").contains("rewrite"))
    }

    // MARK: - Preset factory

    func testMakeCustomPresetMintsAFreshEnabledCustomPreset() {
        let a = AIServiceManager.makeCustomPreset(title: " Rewrite to slovak ", prompt: " rewrite to slovak ")
        let b = AIServiceManager.makeCustomPreset(title: "Rewrite to slovak", prompt: "rewrite to slovak")
        XCTAssertTrue(a.id.hasPrefix("custom_"), "the AI → Actions sheet treats custom_ ids as deletable")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.title, "Rewrite to slovak")
        XCTAssertEqual(a.prompt, "rewrite to slovak")
        XCTAssertTrue(a.isEnabled)
        XCTAssertFalse(AIServiceManager.defaultPresets.contains { $0.id == a.id })
    }

    func testMatchingPromptLookupIgnoresCaseAndWhitespace() {
        let saved = AIActionPreset(id: "custom_1", title: "Rewrite to slovak", prompt: "Rewrite to  slovak", isEnabled: true)
        let presets = AIServiceManager.defaultPresets + [saved]
        XCTAssertEqual(AIServiceManager.preset(in: presets, matchingPrompt: " rewrite to slovak ")?.id, "custom_1")
        XCTAssertNil(AIServiceManager.preset(in: presets, matchingPrompt: "rewrite to czech"))
        XCTAssertNil(AIServiceManager.preset(in: presets, matchingPrompt: "   "))
    }

    // MARK: - Palette wiring

    private final class Recorder {
        var events: [String] = []
    }

    private func context() -> ActionContext {
        let selection = SelectionContext(
            text: "suspicious",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    /// Hosts the palette in a key panel with a one-action catalog, types `query` into the
    /// field the way a user would (through the field editor), then presses `key`.
    private func drivePalette(query: String, aiEnabled: Bool = true, recents: [String] = [], press key: (NSWindow) throws -> Void, recorder: Recorder) throws {
        let catalog: [any Action] = [MockAction(id: "mock.copy", shouldBeEnabled: true)] + recents.map { RecentPromptAction(prompt: $0) }
        let view = PopupSearchView(
            catalog: catalog,
            context: context(),
            resultsAbove: false,
            onResult: { _ in recorder.events.append("result") },
            onExit: { recorder.events.append("exit") },
            onRunAI: { _ in recorder.events.append("run-ai") },
            onRunAIPrompt: { recorder.events.append("ask:\($0):\($1 ? "replace" : "card")") },
            onSaveAIPrompt: { recorder.events.append("save:\($0):\($1 ? "replace" : "card")") },
            aiEnabled: aiEnabled
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

        let field = try XCTUnwrap(Self.findTextField(in: host), "the palette must host a text field")
        panel.makeFirstResponder(field)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let editor = try XCTUnwrap(panel.firstResponder as? NSTextView, "the field must be editing")
        editor.insertText(query, replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

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

    private func commandDigit(_ digit: String, keyCode: UInt16, in panel: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: digit, charactersIgnoringModifiers: digit, isARepeat: false, keyCode: keyCode
        ))
        XCTAssertTrue(panel.performKeyEquivalent(with: event), "⌘\(digit) must reach the palette")
    }

    func testCommandOneOnANonMatchingQueryAsksAI() throws {
        let recorder = Recorder()
        try drivePalette(query: "rewrite  to slovak", press: { try commandDigit("1", keyCode: 18, in: $0) }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["ask:rewrite to slovak:card"],
                       "the query is the instruction, collapsed; ⌘1 shows the card; nothing may perform or exit first")
    }

    func testCommandTwoOnANonMatchingQuerySavesTheTool() throws {
        let recorder = Recorder()
        try drivePalette(query: "rewrite to slovak", press: { try commandDigit("2", keyCode: 19, in: $0) }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["save:rewrite to slovak:card"])
    }

    func testReturnRunsTheAskRowByDefault() throws {
        let recorder = Recorder()
        try drivePalette(query: "rewrite to slovak", press: { panel in
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
            ))
            panel.sendEvent(event)
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["ask:rewrite to slovak:card"], "⏎ shows the result card")
    }

    func testShiftReturnReplacesTheSelectionInstead() throws {
        let recorder = Recorder()
        try drivePalette(query: "rewrite to slovak", press: { panel in
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.shift],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
            ))
            panel.sendEvent(event)
        }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["ask:rewrite to slovak:replace"], "⇧⏎ pastes over the selection")
    }

    // MARK: - Recent prompts as rows

    func testARecentPromptIsFoundByAFragmentAndRunsAsIs() throws {
        let recorder = Recorder()
        try drivePalette(query: "slovak", recents: ["rewrite to slovak"], press: { try commandDigit("1", keyCode: 18, in: $0) }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["ask:rewrite to slovak:card"], "the recent's own text runs, not the fragment")
    }

    func testOnlyRecentMatchesStillOfferSaveAsTheNextRow() throws {
        let recorder = Recorder()
        try drivePalette(query: "slovak", recents: ["rewrite to slovak"], press: { try commandDigit("2", keyCode: 19, in: $0) }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["save:slovak:card"], "row 2 is Save for the typed query")
    }

    func testRecentPromptRowsAreNeverRegisteredActions() {
        let recent = RecentPromptAction(prompt: "rewrite to slovak")
        XCTAssertEqual(recent.title, "rewrite to slovak")
        XCTAssertFalse(ActionIdentity.isAIPreset(recent), "routed by type through onRunAIPrompt, not as a preset")
        let empty = ActionContext(selection: SelectionContext(
            text: "", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default
        ))
        XCTAssertFalse(recent.isEnabled(for: empty), "needs a selection to run on")
    }

    func testAMatchingQueryStillRunsTheActionNotAI() throws {
        let recorder = Recorder()
        // MockAction's title is "Mock"; "moc" is a prefix match, so the result row wins.
        try drivePalette(query: "moc", press: { try commandDigit("1", keyCode: 18, in: $0) }, recorder: recorder)
        XCTAssertEqual(recorder.events, ["result"])
    }

    func testWithAIOffANonMatchingQueryHasNothingToRun() throws {
        let recorder = Recorder()
        try drivePalette(query: "rewrite to slovak", aiEnabled: false, press: { panel in
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18
            ))
            // ⌘-digits are the palette's own while it is open (claimed even with no row, so the
            // key never beeps or leaks to the app underneath) — but nothing may run.
            XCTAssertTrue(panel.performKeyEquivalent(with: event))
        }, recorder: recorder)
        XCTAssertTrue(recorder.events.isEmpty, "with AI off there is no row to run")
    }
}
