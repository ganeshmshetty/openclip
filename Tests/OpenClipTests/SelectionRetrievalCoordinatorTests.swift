import XCTest
import ApplicationServices
import CoreGraphics
@testable import Core
@testable import OpenClip

final class SelectionRetrievalCoordinatorTests: XCTestCase {

    private static func textFieldTarget(
        selectedText: String? = nil,
        role: String = "AXTextField",
        bounds: CGRect? = nil
    ) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: role,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: bounds
        )
    }

    /// An app that exposes no usable AX role for its text (custom-drawn editors/terminals):
    /// everything the gate could key off is absent.
    private static func opaqueTarget(containedInRoles: Set<String> = []) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: nil,
            subRole: nil,
            parentRoles: [],
            containedInRoles: containedInRoles,
            webArea: nil,
            selectedText: nil,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    private static func webAreaTarget(selectedText: String) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: "AXWebArea",
            subRole: nil,
            parentRoles: ["AXGroup"],
            containedInRoles: ["AXGroup"],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    // MARK: - Gate

    func testGateSkipsButtonRole() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "button text", role: "AXButton") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testGateAllowsButtonRoleInsideWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                AXElementInspector.Target(
                    focusedApp: nil,
                    focusedElement: nil,
                    role: "AXButton",
                    subRole: nil,
                    parentRoles: ["AXWebArea"],
                    containedInRoles: ["AXWebArea"],
                    webArea: nil,
                    selectedText: "button text inside web",
                    selectedTextMarkerRange: nil,
                    value: nil,
                    selectedTextRange: nil,
                    bounds: nil
                )
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "button text inside web")
    }

    func testUnknownCursorProceedsEvenWhenNotAllowed() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "proceed") }
        )
        let policy = AppPolicyContext(
            retrievalMode: .axTextControl,
            gate: SelectionGatePolicy(allowedCursors: [.beam])
        )
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "proceed")
    }

    func testDisallowedCursorBlocksRetrieval() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "blocked") }
        )
        let policy = AppPolicyContext(
            retrievalMode: .axTextControl,
            gate: SelectionGatePolicy(allowedCursors: [.beam])
        )
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .arrow
        )
        XCTAssertNil(result)
    }

    // MARK: - Modes

    func testAXTextControlReturnsTextFromFixtureTarget() async {
        let bounds = CGRect(x: 1, y: 2, width: 30, height: 4)
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "hello", bounds: bounds) }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "hello")
        XCTAssertEqual(result?.bounds, bounds)
    }

    func testAXWebAreaReturnsTextFromFixtureTarget() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "web text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web text")
    }

    func testAXWebAreaSettleRetryReInspectsUntilTextSettles() async {
        final class InspectCallCount: @unchecked Sendable { var value = 0 }
        let calls = InspectCallCount()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                calls.value += 1
                if calls.value <= 2 {
                    return Self.webAreaTarget(selectedText: "")
                }
                return Self.webAreaTarget(selectedText: "settled web text")
            },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "settled web text")
        XCTAssertGreaterThan(calls.value, 2)
    }

    func testBrowserModeUsesWebAreaSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "web selection") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "web selection")
    }

    func testBrowserModeNilFallsBackToKeyboardCopy() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "copy fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copy fallback")
    }

    private actor CopyCallTracker {
        var copyInvoked = false
        func recordCopy() { copyInvoked = true }
    }

    func testAllowCopyFallbackFalseSkipsCopyCapture() async {
        let tracker = CopyCallTracker()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                await tracker.recordCopy()
                return TextResult(text: "should not be called")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.openai.codex"),
            policy: policy,
            cursor: .unknown,
            allowCopyFallback: false
        )
        XCTAssertNil(result)
        let invoked = await tracker.copyInvoked
        XCTAssertFalse(invoked, "copyCapture must not be invoked when allowCopyFallback is false")
    }

    func testRetrieveDetailsIdentifiesEditableTextControl() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextField") },
            copyCapture: { _ in nil }
        )
        let outcome = await coordinator.retrieveDetails(
            for: AppIdentity(bundleIdentifier: "com.openai.codex"),
            policy: AppPolicyContext.default,
            cursor: CursorClass.unknown,
            allowCopyFallback: false
        )
        XCTAssertNil(outcome.result)
        XCTAssertTrue(outcome.isEditable, "AXTextField must be identified as editable context")
    }


    // MARK: - Copy modes

    func testMenuCopyProceedsWithoutConfirmedSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .default)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testMenuCopyStartsAtMenuCopyEvenWhenAXTextAvailable() async {
        // A menu-copy rule starts the chain at menu copy, so it never performs the AX text strategy
        // above it — even when the target happens to expose AX text.
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "ax text") },
            copyCapture: { _ in TextResult(text: "captured via menu copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured via menu copy")
    }

    func testKeyboardCopyStartsAtKeyboardCopyEvenWhenAXTextAvailable() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "ax text") },
            copyCapture: { _ in TextResult(text: "captured keyboard copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured keyboard copy")
    }

    func testKeyboardCopyHasNoFallbackBelowIt() async {
        // keyboard-copy is the terminal strategy in the chain, so a failed keyboard copy does not
        // fall through to menu copy.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    func testMenuCopyHasNoFallbackToKeyboardCopy() async {
        // menu-copy is strict for terminals and does not fall through to keyboard-copy, avoiding double timeouts.
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return nil
            }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.mitchellh.ghostty"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 1)
    }

    func testCopyCaptureNilReturnsNil() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.microsoft.VSCode"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testMenuCopyCaptureNilReturnsNil() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    // MARK: - Select-all (⌘A) gating for copy modes

    func testSelectAllMenuCopySkippedOnNonTextElement() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXOutline") },
            copyCapture: { _ in TextResult(text: "should not copy rows") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.finder"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    func testSelectAllMenuCopySkippedOnNonTextElementWithoutSelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "row text", role: "AXTable") },
            copyCapture: { _ in TextResult(text: "should not copy") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.mail"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    func testSelectAllMenuCopyProceedsOnTextElement() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "captured select-all text") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "captured select-all text")
    }

    /// Regression (from a real log): in Zed a drag and a ⇧+arrow both retrieved fine through the
    /// copy strategy one second apart, while ⌘A in the same element was refused — the guard
    /// demanded a *known* text role, and editors/terminals that draw their own text expose none.
    /// Only a recognized row container may refuse a select-all now.
    func testSelectAllProceedsOnAppWithNoRecognizableAXRole() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.opaqueTarget() },
            copyCapture: { _ in TextResult(text: "captured select-all text") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "dev.zed.Zed"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "captured select-all text")
    }

    /// A row container nested above the focused element still refuses — the Finder/Mail case the
    /// guard exists for reaches it through `containedInRoles`, not the focused role.
    func testSelectAllSkippedInsideRowContainer() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.opaqueTarget(containedInRoles: ["AXScrollArea", "AXOutline"]) },
            copyCapture: { _ in TextResult(text: "should not copy rows") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.finder"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertNil(result)
    }

    /// A text field being edited inside a table is text, not a row selection.
    func testSelectAllProceedsInTextFieldInsideTable() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "cell text", role: "AXTextField") },
            copyCapture: { _ in TextResult(text: "cell text") }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Numbers"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "cell text")
    }

    func testSelectAllDoesNotGateNonCopyModes() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "selected text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown,
            isSelectAll: true
        )
        XCTAssertEqual(result?.text, "selected text")
    }

    // MARK: - Fallback cascade

    func testAXTextControlFallsBackToCopyWhenAXReadIsEmpty() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "copied fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied fallback")
    }

    func testBrowserScriptFallsBackThroughWebAreaThenCopy() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "") },
            copyCapture: { _ in TextResult(text: "browser copy fallback") }
        )
        let policy = AppPolicyContext(retrievalMode: .browserScript)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Safari"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "browser copy fallback")
    }

    // MARK: - Blank-text filtering

    func testRetrieveRejectsWhitespaceOnlySelection() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "   \n  ") },
            copyCapture: { _ in nil }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testRetrieveRejectsWhitespaceOnlyCopyCapture() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil, role: "AXTextArea") },
            copyCapture: { _ in TextResult(text: "  ") }
        )
        let policy = AppPolicyContext(retrievalMode: .menuCopy, gate: .lenient)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
    }

    func testBlankAXTextFallsThroughToCopyFallback() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "   \t  ") },
            copyCapture: { _ in TextResult(text: "copied text") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied text")
    }

    func testStrictlyNativeAppDoesNotFallbackToKeyboardCopy() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected copy")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(result)
        XCTAssertEqual(counter.calls, 0)
    }

    func testNotesResolvesKeyboardCopyFallback() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "copied from notes") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Notes"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied from notes")
    }

    func testNativeAppWithEmbeddedWebAreaCascadesToWebArea() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "mail web body") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.mail"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "mail web body")
    }

    func testPreviewAppFallsBackToKeyboardCopy() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in TextResult(text: "copied from preview pdf") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Preview"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "copied from preview pdf")
    }

    // MARK: - Rich-content enrichment

    func testTextOnlyWebAreaWinEnrichesFromPasteboardCapture() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "plain selection") },
            copyCapture: { _ in TextResult(text: "rich selection", html: "<b>rich</b> selection") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "rich selection")
        XCTAssertEqual(result?.html, "<b>rich</b> selection")
    }

    func testNativeAppTextOnlyWinDoesNotFireCopyCapture() async throws {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "native text") },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "unexpected", html: "<b>unexpected</b>")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)
        let nativeBundleID = try XCTUnwrap(DefaultAppRules.nativeApps.first)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: nativeBundleID),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "native text")
        XCTAssertNil(result?.html)
        XCTAssertEqual(counter.calls, 0)
    }

    func testKeyboardCopySkipsEnrichmentCapture() async {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { _ in
                counter.calls += 1
                return TextResult(text: "captured", html: "<b>captured</b>")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .keyboardCopy)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "captured")
        XCTAssertEqual(result?.html, "<b>captured</b>")
        XCTAssertEqual(counter.calls, 1)
    }

    func testEnrichmentKeepsOriginalWhenCaptureYieldsNoRichContent() async {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.webAreaTarget(selectedText: "plain selection") },
            copyCapture: { _ in TextResult(text: "plain capture") }
        )
        let policy = AppPolicyContext(retrievalMode: .axWebArea)
        let result = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.google.Chrome"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertEqual(result?.text, "plain selection")
        XCTAssertNil(result?.html)
    }

    // MARK: - Inspect concurrency gate

    /// Regression: overlapping gestures (quick re-selection, double-click, hotkey+monitor races)
    /// used to fail fast on the single AX slot — popup for neither selection. Each concurrent
    /// read now gets its own permit and delivers independently.
    func testConcurrentRetrievesBothDeliver() async {
        let inspectStarted = expectation(description: "both inspects started")
        inspectStarted.expectedFulfillmentCount = 2
        inspectStarted.assertForOverFulfill = true
        let unblock = DispatchSemaphore(value: 0)

        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                inspectStarted.fulfill()
                unblock.wait()
                return Self.textFieldTarget(selectedText: "overlap text")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        async let firstResult = coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        async let secondResult = coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )

        await fulfillment(of: [inspectStarted], timeout: 2.0)
        unblock.signal()
        unblock.signal()

        let first = await firstResult
        let second = await secondResult
        XCTAssertEqual(first?.text, "overlap text", "first overlapping gesture must still deliver")
        XCTAssertEqual(second?.text, "overlap text", "second overlapping gesture must not be dropped")
    }

    /// Regression: the permit was released only when the underlying blocking inspect returned,
    /// so one slow/hung app kept every subsequent popup missing for seconds. The permit must free
    /// at the caller's watchdog deadline even while that worker is still parked.
    func testInspectPermitFreesAtWatchdogDeadlineWhileWorkerStillHung() async {
        // Worker #1 parks far past axReadTimeout (0.5s): its caller gets nil from the watchdog
        // while the AX queue thread stays blocked on the semaphore.
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer { zombieUnblock.signal() }
        let hungCoordinator = SelectionRetrievalCoordinator(
            inspect: {
                zombieUnblock.wait()
                return Self.textFieldTarget(selectedText: "zombie")
            }
        )
        // A fresh coordinator shares the process-wide gate — proving the permit crossed instances.
        let freshCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        let hungResult = await hungCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(hungResult, "watchdog must return nil for the hung read")

        // The deadline already settled the hung call; a new retrieval must proceed immediately.
        let freshStart = Date()
        let freshResult = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(freshStart), Constants.axReadTimeout,
                          "new read must not wait behind the abandoned hung worker")
        XCTAssertEqual(freshResult?.text, "fresh",
                       "permit must be usable again right after the watchdog deadline")

        zombieUnblock.signal() // release the abandoned AX worker thread
    }

    /// The concurrency cap still bounds pile-up: at `Constants.axMaxConcurrentInspects`
    /// simultaneously-awaited reads, further requests skip instead of stacking more workers.
    func testConcurrencyCapFailsFastWhenSaturated() async {
        let inspectStarted = expectation(description: "cap-filling inspects started")
        inspectStarted.expectedFulfillmentCount = Constants.axMaxConcurrentInspects
        inspectStarted.assertForOverFulfill = true
        let unblock = DispatchSemaphore(value: 0)

        let coordinator = SelectionRetrievalCoordinator(
            inspect: {
                inspectStarted.fulfill()
                unblock.wait()
                return Self.textFieldTarget(selectedText: "parked")
            }
        )
        let policy = AppPolicyContext(retrievalMode: .axTextControl)

        var parkedResults: [Task<TextResult?, Never>] = []
        for _ in 0..<Constants.axMaxConcurrentInspects {
            parkedResults.append(Task {
                await coordinator.retrieve(
                    for: AppIdentity(bundleIdentifier: "com.test.app"),
                    policy: policy,
                    cursor: .unknown
                )
            })
        }
        await fulfillment(of: [inspectStarted], timeout: 2.0)

        let start = Date()
        let overflow = await coordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: policy,
            cursor: .unknown
        )
        XCTAssertNil(overflow, "saturated gate must skip the extra read instead of piling up")
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3,
                          "the overflow read must fail fast, not queue")

        unblock.signal()
        for _ in 0..<Constants.axMaxConcurrentInspects { unblock.signal() }
        for task in parkedResults {
            let value = await task.value
            XCTAssertEqual(value?.text, "parked")
        }
    }

    /// A blocked Edit ▸ Copy press must release `inspectGate` at `axReadTimeout`.
    /// A new inspect must then complete immediately.
    func testMenuCopyPressPermitFreesAtWatchdogDeadlineWhileWorkerStillHung() async {
        let pressStarted = expectation(description: "hung menu press started")
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer { zombieUnblock.signal() }

        let hungCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { trigger in
                await MainActor.run { trigger() }
                return nil
            },
            menuPress: { _ in
                pressStarted.fulfill()
                zombieUnblock.wait()
            }
        )
        let freshCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let menuPolicy = AppPolicyContext(retrievalMode: .menuCopy)
        let inspectPolicy = AppPolicyContext(retrievalMode: .axTextControl)

        async let hungResult = hungCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
            policy: menuPolicy,
            cursor: .unknown
        )

        await fulfillment(of: [pressStarted], timeout: 2.0)
        _ = await hungResult

        try? await Task.sleep(nanoseconds: UInt64((Constants.axReadTimeout + 0.1) * 1_000_000_000))

        let freshStart = Date()
        let freshResult = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: inspectPolicy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(freshStart), Constants.axReadTimeout,
                          "new read must not wait behind the abandoned hung menu press")
        XCTAssertEqual(freshResult?.text, "fresh",
                       "permit must be usable again right after the press watchdog deadline")
    }

    /// Four blocked Edit ▸ Copy presses must not keep `inspectGate` full.
    /// After `axReadTimeout`, a new inspect must succeed.
    func testFourHungMenuCopyPressesDoNotPermanentlyLockOutInspect() async {
        let starts = PressStartSignal()
        let zombieUnblock = DispatchSemaphore(value: 0)
        defer {
            for _ in 0..<Constants.axMaxConcurrentInspects { zombieUnblock.signal() }
        }

        let hungCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: nil) },
            copyCapture: { trigger in
                await MainActor.run { trigger() }
                return nil
            },
            menuPress: { _ in
                starts.signal()
                zombieUnblock.wait()
            }
        )
        let freshCoordinator = SelectionRetrievalCoordinator(
            inspect: { Self.textFieldTarget(selectedText: "fresh") }
        )
        let menuPolicy = AppPolicyContext(retrievalMode: .menuCopy)
        let inspectPolicy = AppPolicyContext(retrievalMode: .axTextControl)

        var hungTasks: [Task<TextResult?, Never>] = []
        for index in 1...Constants.axMaxConcurrentInspects {
            hungTasks.append(Task {
                await hungCoordinator.retrieve(
                    for: AppIdentity(bundleIdentifier: "com.apple.Terminal"),
                    policy: menuPolicy,
                    cursor: .unknown
                )
            })
            await starts.waitUntil(index)
        }

        let overflowStart = Date()
        let overflow = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: inspectPolicy,
            cursor: .unknown
        )
        XCTAssertNil(overflow, "saturated gate must skip inspect while four hung presses hold permits")
        XCTAssertLessThan(Date().timeIntervalSince(overflowStart), 0.3,
                          "the overflow read must fail fast, not queue")

        try? await Task.sleep(nanoseconds: UInt64((Constants.axReadTimeout + 0.1) * 1_000_000_000))

        let recoveredStart = Date()
        let recovered = await freshCoordinator.retrieve(
            for: AppIdentity(bundleIdentifier: "com.test.app"),
            policy: inspectPolicy,
            cursor: .unknown
        )
        XCTAssertLessThan(Date().timeIntervalSince(recoveredStart), Constants.axReadTimeout,
                          "inspect must not stay locked out after press watchdogs fire")
        XCTAssertEqual(recovered?.text, "fresh")

        for task in hungTasks { _ = await task.value }
    }
}

/// Counts started menu presses.
/// Tests start one blocked `.menuCopy` retrieve at a time.
/// This keeps inspect permits and press permits from overlapping.
private final class PressStartSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func signal() {
        lock.lock()
        count += 1
        let n = count
        let ready = waiters.filter { n >= $0.0 }
        waiters.removeAll { $0.0 <= n }
        lock.unlock()
        ready.forEach { $0.1.resume() }
    }

    func waitUntil(_ target: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if count >= target {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append((target, continuation))
            lock.unlock()
        }
    }
}

