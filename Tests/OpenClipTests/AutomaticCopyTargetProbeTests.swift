import XCTest
@testable import OpenClip

final class AutomaticCopyTargetProbeTests: XCTestCase {
    func testMatchesVSCodeKeybindingSearchInputBySyntheticFocusClass() {
        let ancestors: [AutomaticCopyTargetProbe.AncestorNode] = [
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["ibwrapper"]),
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["monaco-inputbox", "idle", "synthetic-focus"]),
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["search-container"])
        ]

        XCTAssertTrue(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextField",
                focusedPlaceholder: nil,
                ancestorNodes: ancestors
            )
        )
    }

    func testMatchesVSCodeKeybindingInputByPlaceholder() {
        XCTAssertTrue(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextField",
                focusedPlaceholder: "Recording Keys. Press Escape to exit (⇅ for history)",
                ancestorNodes: []
            )
        )
        XCTAssertTrue(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextField",
                focusedPlaceholder: "Press desired key combination and then press ENTER.",
                ancestorNodes: []
            )
        )
    }

    func testMatchesKeyboardShortcutsDialogSearchContainer() {
        let ancestors: [AutomaticCopyTargetProbe.AncestorNode] = [
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["search-container"]),
            .init(role: "AXGroup", subrole: "AXApplicationDialog", title: "Keyboard Shortcuts", description: "Keyboard Shortcuts", domClasses: ["part", "editor", "modal-editor-part"])
        ]

        XCTAssertTrue(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextField",
                focusedPlaceholder: "Type to search",
                ancestorNodes: ancestors
            )
        )
    }

    func testDoesNotMatchMainCodeEditorOrRegularInputBox() {
        let syntheticAncestors: [AutomaticCopyTargetProbe.AncestorNode] = [
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["monaco-inputbox", "idle", "synthetic-focus"])
        ]
        XCTAssertFalse(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextArea",
                focusedPlaceholder: "Recording Keys",
                ancestorNodes: syntheticAncestors
            )
        )

        let regularFindAncestors: [AutomaticCopyTargetProbe.AncestorNode] = [
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["ibwrapper"]),
            .init(role: "AXGroup", subrole: nil, title: nil, description: nil, domClasses: ["monaco-inputbox", "idle"])
        ]
        XCTAssertFalse(
            AutomaticCopyTargetProbe.isKeyRecordingInput(
                focusedRole: "AXTextField",
                focusedPlaceholder: "Find",
                ancestorNodes: regularFindAncestors
            )
        )
    }

    func testTimeoutReturnsFalse() async {
        let probe = AutomaticCopyTargetProbe(timeout: 0.05) { _, _ in
            Thread.sleep(forTimeInterval: 0.2)
            return true
        }
        let suppressed = await probe.shouldSuppressCopy(pid: 12345)
        XCTAssertFalse(suppressed)
    }
}
