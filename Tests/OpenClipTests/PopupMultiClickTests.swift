// PopupMultiClickTests.swift
// OpenClip
//
// Pins the popup-side half of triple-click handling: a third press must not dismiss the word
// popup that the second press opened, so the paragraph result can replace its content in place.
import AppKit
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class PopupMultiClickTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    private func context(text: String) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test.source", processIdentifier: 99999),
            cursorPosition: CGPoint(x: 400, y: 300)
        )
    }

    private func thirdPress() -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 3,
            pressure: 1
        )!
    }

    func testThirdPressKeepsWordPopupUpForParagraphReplacement() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        controller.show(for: context(text: "word"))
        XCTAssertTrue(controller.isVisible)

        // Age the session past the 100 ms "gesture that opened it" grace so only the
        // clickCount>=3 rule can keep the popup up.
        controller.sessionShowTime = ProcessInfo.processInfo.systemUptime - 0.2
        controller.handleEvent(thirdPress())

        XCTAssertTrue(controller.isVisible, "a triple-click's third press must not dismiss the word popup")
        XCTAssertEqual(controller.currentActionContext?.selection.text, "word")

        controller.show(for: context(text: "paragraph text"))

        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.currentActionContext?.selection.text, "paragraph text")
    }
}
