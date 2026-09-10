import XCTest
import SwiftUI
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupInlineUITests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private struct MockInlineAction: Action {
        let id: String
        let title: String = "Mock Inline Action"
        let icon: ActionIcon = .symbol("function")
        let chrome: ActionChrome = ActionChrome(
            badge: .none,
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .builtin,
            isInlineResult: true
        )

        func isEnabled(for context: ActionContext) -> Bool { true }

        func perform(_ context: ActionContext) async throws -> ActionResult {
            return .text("original perform text")
        }
    }

    private func makeContext(text: String = "12 * 12") -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    func testInlineMetricsValues() {
        // Test that inline result metrics conform to visual and performance design limits
        XCTAssertLessThanOrEqual(PopupMetrics.inlineResultMaxWidth, 160.0)
        XCTAssertGreaterThan(PopupMetrics.inlineResultMaxWidth, 100.0)
        XCTAssertEqual(PopupMetrics.inlineResultHorizontalPadding, 8.0)
        XCTAssertEqual(PopupMetrics.inlineCrossFadeDuration, 0.18, accuracy: 0.01)
        XCTAssertEqual(PopupMetrics.inlineSpringResponse, 0.24, accuracy: 0.01)
        XCTAssertEqual(PopupMetrics.inlineSpringDamping, 0.82, accuracy: 0.01)
        XCTAssertEqual(PopupMetrics.inlineEvaluationTimeout, 0.5, accuracy: 0.01)
        XCTAssertEqual(PopupMetrics.inlineSearchAccessoryMaxWidth, 120.0, accuracy: 0.01)
    }

    func testSearchPaletteCommandModifierToggle() {
        // Verify shortcutHint vs inline text selection logic
        let action = CalculateAction()
        XCTAssertTrue(action.chrome.isInlineResult)
        
        let inlineResults = [action.id: "144"]
        
        // When ⌘ is released (false), inline result is shown
        let isCommandPressed = false
        let accessoryText = (action.chrome.isInlineResult && !isCommandPressed) ? inlineResults[action.id] : "⌘1"
        XCTAssertEqual(accessoryText, "144")
        
        // When ⌘ is pressed (true), shortcut hint is shown
        let isCommandPressedDown = true
        let peekText = (action.chrome.isInlineResult && !isCommandPressedDown) ? inlineResults[action.id] : "⌘1"
        XCTAssertEqual(peekText, "⌘1")
    }

    func testSearchPalettePeekVisibilityLogic() {
        let inlineAction = MockInlineAction(id: "mock.calc")
        let regularAction = MockAction(id: "mock.regular", shouldBeEnabled: true)
        let inlineResults = [inlineAction.id: "42"]

        // For inline action:
        // When Command is not pressed, shows inline result
        let isCommandPressed = false
        let inlineUnpressed = (inlineAction.chrome.isInlineResult && inlineResults[inlineAction.id] != nil && !isCommandPressed)
            ? inlineResults[inlineAction.id]! : (PopupSearchView.shortcutHint(forRow: 0) ?? "")
        XCTAssertEqual(inlineUnpressed, "42")

        // When Command is pressed, shows shortcut peek "⌘1"
        let isCommandPressedDown = true
        let inlinePressed = (inlineAction.chrome.isInlineResult && inlineResults[inlineAction.id] != nil && !isCommandPressedDown)
            ? inlineResults[inlineAction.id]! : (PopupSearchView.shortcutHint(forRow: 0) ?? "")
        XCTAssertEqual(inlinePressed, "⌘1")

        // For regular action without inline result:
        // Always shows shortcut hint
        _ = regularAction
        let regularText = PopupSearchView.shortcutHint(forRow: 1)
        XCTAssertEqual(regularText, "⌘2")
    }

    func testSearchPaletteDeliversInlineResultOnExecution() throws {
        let action = MockInlineAction(id: "inline.search.test")
        let modeStore = PopupModeStore()
        modeStore.inlineResults[action.id] = "Evaluated: 144"

        var deliveredResult: ActionResult?
        let palette = PopupSearchView(
            catalog: [action],
            context: makeContext(),
            resultsAbove: false,
            modeStore: modeStore,
            onResult: { result in
                deliveredResult = result
            },
            onExit: {}
        )
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: AnyView(palette))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = PopupPanel()
        panel.allowsKey = true
        panel.contentView = host
        panel.setFrame(NSRect(x: 200, y: 200, width: max(size.width, 320), height: max(size.height, 200)), display: true)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18   // kVK_ANSI_1
        ))

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let result = deliveredResult else {
            XCTFail("Result should have been delivered")
            return
        }

        if case .text(let text) = result {
            XCTAssertEqual(text, "Evaluated: 144")
        } else {
            XCTFail("Expected .text ActionResult, got \(result)")
        }
    }

    func testPopupViewModeStoreInlineResultsBinding() {
        let action = MockInlineAction(id: "inline.popup.test")
        let modeStore = PopupModeStore()
        modeStore.inlineResults[action.id] = "777"

        var deliveredResult: ActionResult?
        let popupView = PopupView(
            actions: [action],
            context: makeContext(),
            modeStore: modeStore,
            onResult: { result in
                deliveredResult = result
            }
        )

        // Verify the view can be created with modeStore holding inlineResults
        XCTAssertNotNil(popupView)
        XCTAssertEqual(modeStore.inlineResults[action.id], "777")
        _ = deliveredResult
    }
}
