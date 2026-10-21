import XCTest
import AppKit
import Core
@testable import OpenClip

final class ActionResultDeliveryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    /// Asserts `result` equals `expected` by pattern matching (ActionResult is not Equatable).
    private func assertCase(_ result: ActionResult, _ expected: ActionResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.paste(let a), .paste(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.copy(let a), .copy(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.text(let a), .text(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.cut(let a), .cut(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.openURL(let a), .openURL(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.success, .success), (.none, .none), (.simulatePaste, .simulatePaste): XCTAssertTrue(true, message, file: file, line: line)
        case (.sequence(let a), .sequence(let b)):
            XCTAssertEqual(a.count, b.count, message.isEmpty ? "sequence length" : message, file: file, line: line)
            for (item, expectedItem) in zip(a, b) {
                assertCase(item, expectedItem, message, file: file, line: line)
            }
        default: XCTFail(message.isEmpty ? "unexpected result \(result)" : "\(message): unexpected result \(result)", file: file, line: line)
        }
    }

    // MARK: - Primary click + can paste → paste

    func testPrimaryClickCanPastePastes() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .primary,
            canPaste: true,
            delivery: .none
        )
        assertCase(result, .paste("hello"))
    }

    // MARK: - Secondary (right-click / shift) always copies

    func testSecondaryCopiesEvenWhenPasteAvailable() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Cannot paste → copy

    func testCannotPasteCopies() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .paste("hello"),
            clickIntent: .primary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    // MARK: - Non-paste results pass through untouched

    func testCopyStaysCopy() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .copy("hello"),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .copy("hello"))
    }

    func testNativeCopyPreservesClickBehaviorAndReportsCopied() {
        let selection = SelectionContext(text: "Selected", selectionGeneration: 7)
        for intent in [ActionResultDelivery.ClickIntent.primary, .secondary] {
            let (result, toast) = ActionResultDelivery.resolve(
                raw: .copySelection(selection), clickIntent: intent, canPaste: false, delivery: .none
            )
            guard case .copySelection(let copied) = result else { return XCTFail("Native Copy must stay native") }
            XCTAssertEqual(copied.selectionGeneration, 7)
            XCTAssertEqual(toast?.message, "Copied")
        }
    }

    func testCutStaysCut() {
        let (result, _) = ActionResultDelivery.resolve(
            raw: .cut("hello"),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .cut("hello"))
    }

    func testNonTextResultsPassThrough() {
        let url = URL(string: "https://example.com")!
        let (result, _) = ActionResultDelivery.resolve(
            raw: .openURL(url),
            clickIntent: .secondary,
            canPaste: false,
            delivery: .none
        )
        assertCase(result, .openURL(url))
    }

    // MARK: - Primary/secondary selection

    func testPrimaryUsesRawResult() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        assertCase(r, .paste("a"))
    }

    func testSecondaryWithoutDeclaredSecondaryCopiesPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .copy("a"))
    }

    func testSecondaryWithNonPastePrimaryStaysPrimary() {
        let (r, _) = ActionResultDelivery.resolve(raw: .openURL(URL(string: "https://x")!), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .openURL(URL(string: "https://x")!))
    }

    func testSecondaryUsesDeclaredSecondary() {
        let d = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: d)
        assertCase(r, .openURL(URL(string: "https://alt")!))
    }

    // MARK: - Probe applies to whichever result is chosen

    func testProbeAppliesToDeclaredPasteSecondary() {
        let d = ActionDelivery(secondary: .paste("a"))
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: false, delivery: d)
        assertCase(r, .copy("a"))   // declared paste still downgrades when target can't paste
    }

    func testProbeAppliesToPrimary() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: false, delivery: .none)
        assertCase(r, .copy("a"))
    }

    // MARK: - Rich content delivery (pasteContent/copyContent)

    private func assertPayload(_ result: ActionResult, _ expected: ActionResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.pasteContent(let a), .pasteContent(let b)), (.copyContent(let a), .copyContent(let b)):
            XCTAssertEqual(a.plainText, b.plainText, message, file: file, line: line)
            XCTAssertEqual(a.html, b.html, message, file: file, line: line)
            XCTAssertEqual(a.rtf, b.rtf, message, file: file, line: line)
        default:
            XCTFail(message.isEmpty ? "unexpected result \(result)" : "\(message): unexpected result \(result)", file: file, line: line)
        }
    }

    private var richPayload: RichPasteboardPayload {
        RichPasteboardPayload(plainText: "hi", rtf: nil, html: "<b>hi</b>")
    }

    func testPrimaryRichPasteStaysPasteWhenTargetCanPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .primary, canPaste: true, delivery: .none)
        assertPayload(r, .pasteContent(richPayload))
        XCTAssertNil(toast)
    }

    func testProbeDowngradesRichPasteWhenTargetCannotPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .primary, canPaste: false, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    func testSecondaryClickOnRichPasteDerivesCopyContent() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    func testSecondaryClickOnRichPasteDowngradesCopyWhenTargetCannotPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .pasteContent(richPayload), clickIntent: .secondary, canPaste: false, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
    }

    func testExplicitCopyContentNeverDowngraded() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .copyContent(richPayload), clickIntent: .primary, canPaste: true, delivery: .none)
        assertPayload(r, .copyContent(richPayload))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
        XCTAssertEqual(toast?.style, .success)
    }

    // MARK: - Toast

    func testDefaultCopiedToastOnDerivedCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
        XCTAssertEqual(toast?.style, .success)
    }

    func testNoDefaultToastOnHonoredPaste() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertNil(toast)
    }

    func testDefaultToastOnNativeCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .copy("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
        XCTAssertEqual(toast?.style, .success)
    }

    func testDeclaredPrimaryToastOverridesDefault() {
        let t = StatusFeedback(message: "Saved", style: .info)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: ActionDelivery(primaryToast: t))
        XCTAssertEqual(toast, t)
    }

    func testDeclaredSecondaryToastUsed() {
        let t = StatusFeedback(message: "Copied alt", style: .success)
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: ActionDelivery(secondaryToast: t))
        XCTAssertEqual(toast, t)
    }

    // MARK: - Implicit returned text (.text) + user preference

    func testTextWithPastePreferencePastesWhenCanPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .paste)
        assertCase(r, .paste("hello"))
        XCTAssertNil(toast, "an honored paste fires no companion toast")
    }

    func testTextWithPastePreferenceCopiesWhenCannotPaste() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: false, delivery: .none, preference: .paste)
        assertCase(r, .copy("hello"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"), "a paste context delivered as a copy fires the default Copied toast")
    }

    func testTextWithCopyPreferenceCopiesWithToast() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .copy)
        assertCase(r, .copy("hello"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"), "a delivered copy outcome fires the default Copied toast")
    }

    func testTextWithPreviewPreferenceStaysText() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .preview)
        assertCase(r, .text("hello"))
        XCTAssertNil(toast)
    }

    func testTextWithPreviewPreferenceIgnoresProbe() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: false, delivery: .none, preference: .preview)
        assertCase(r, .text("hello"))
    }

    func testTextNilPreferencePrimaryDefaultsToPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none)
        assertCase(r, .paste("hello"))
    }

    func testTextNilPreferenceSecondaryDefaultsToCopy() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .secondary, canPaste: true, delivery: .none)
        assertCase(r, .copy("hello"))
    }

    func testTextWithPreviewPreferenceSecondaryStaysInCard() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .secondary, canPaste: true, delivery: .none, preference: .preview)
        assertCase(r, .text("hello"), "Show in card applies to secondary clicks too")
        XCTAssertNil(toast)
    }

    func testRecommendedPreviewSecondaryStillCopies() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .secondary, canPaste: true, delivery: .none, recommendedResult: .preview)
        assertCase(r, .copy("hello"), "only the user's own Show in card choice overrides the clipboard invariant")
    }

    func testPastePreferenceSecondaryStillCopies() {
        let (r, _) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .secondary, canPaste: true, delivery: .none, preference: .paste)
        assertCase(r, .copy("hello"))
    }

    func testPreviewPreferenceSecondaryExplicitPasteStillCopies() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none, preference: .preview)
        assertCase(r, .copy("a"))
    }

    func testDeclaredSecondaryWinsOverTextPreference() {
        let d = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let (r, _) = ActionResultDelivery.resolve(raw: .text("a"), clickIntent: .secondary, canPaste: true, delivery: d, preference: .preview)
        assertCase(r, .openURL(URL(string: "https://alt")!))
    }

    func testPreferenceIsNoOpForExplicitPaste() {
        let (r, _) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: false, delivery: .none, preference: .preview)
        assertCase(r, .copy("a"), "an explicit .paste is never previewed — the probe downgrade still applies")
    }

    func testPreferenceIsNoOpForExplicitCopy() {
        let (r, _) = ActionResultDelivery.resolve(raw: .copy("a"), clickIntent: .primary, canPaste: false, delivery: .none, preference: .preview)
        assertCase(r, .copy("a"))
    }

    // MARK: - Sequences

    func testSequenceResolvesEachItem() {
        let pasted = ActionResultDelivery.resolve(
            raw: .sequence([.text("a"), .paste("b")]),
            clickIntent: .primary,
            canPaste: false,
            delivery: .none,
            preference: .paste
        )
        assertCase(pasted.result, .sequence([.copy("a"), .copy("b")]))
        XCTAssertTrue(pasted.result.dismissesPopup)

        let preview = ActionResultDelivery.resolve(
            raw: .sequence([.text("a")]),
            clickIntent: .primary,
            canPaste: false,
            delivery: .none,
            preference: .preview
        )
        assertCase(preview.result, .sequence([.text("a")]))
        XCTAssertFalse(preview.result.dismissesPopup)

        let declared = ActionDelivery(secondary: .openURL(URL(string: "https://alt")!))
        let replaced = ActionResultDelivery.resolve(
            raw: .sequence([.paste("a"), .notify(title: "t", body: "b")]),
            clickIntent: .secondary,
            canPaste: true,
            delivery: declared
        )
        assertCase(replaced.result, .openURL(URL(string: "https://alt")!))
    }

    // MARK: - RuleEngine propagates denyPaste

    @MainActor
    func testRuleEngineResolvesDenyPaste() {
        RuleEngine.shared.reset()
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.example.terminal"], denyPaste: true))
        let policy = RuleEngine.shared.resolvePolicies(for: "com.example.terminal")
        XCTAssertTrue(policy.denyPaste)
        RuleEngine.shared.reset()
    }

    @MainActor
    func testRuleEngineDefaultDenyPasteIsFalse() {
        RuleEngine.shared.reset()
        let policy = RuleEngine.shared.resolvePolicies(for: "com.example.anything")
        XCTAssertFalse(policy.denyPaste)
    }

    @MainActor
    func testTerminalHasDefaultDenyPaste() {
        RuleEngine.shared.reset()
        let policy = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertTrue(policy.denyPaste)
        let iTermPolicy = RuleEngine.shared.resolvePolicies(for: "com.googlecode.iterm2")
        XCTAssertTrue(iTermPolicy.denyPaste)
    }

    // MARK: - Controller wiring: the delivery inputs must be snapshotted before hide() clears them

    @MainActor
    private func awaitDelivery(from handler: RecordingHandler) async throws -> ActionResult {
        let deadline = Date().addingTimeInterval(3.0)
        while handler.results.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(handler.results.isEmpty, "effect delivery never reached the handler")
        return handler.results.first!
    }

    @MainActor
    private func awaitDelivery(at index: Int, from handler: RecordingHandler) async throws -> ActionResult {
        let deadline = Date().addingTimeInterval(3.0)
        while handler.results.count <= index && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertGreaterThan(handler.results.count, index, "effect delivery did not reach the handler at index \(index)")
        return handler.results[index]
    }

    /// Polls `toast.isLoading` until it clears or the deadline passes; state-based, not a fixed sleep, so it is not flaky.
    @MainActor
    private func awaitLoadingFade(toast: ToastPanelController) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Polls until the toast shows `message` or the deadline passes, so `perform` can settle first.
    @MainActor
    private func awaitToastMessage(_ toast: ToastPanelController, _ message: String) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.currentFeedback?.message != message && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @MainActor
    private func shownController(resultHandler: ActionResultHandler,
                                 pasteProbe: PasteAvailabilityProbing,
                                 appPolicy: AppPolicyContext,
                                 toastController: ToastPanelController = ToastPanelController(),
                                 settingsStore: SettingsStore = MemorySettingsStore(),
                                 source: SelectionSource = .selection) -> PopupWindowController {
        let controller = PopupWindowController(resultHandler: resultHandler, pasteProbe: pasteProbe, toastController: toastController, settingsStore: settingsStore)
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: appPolicy,
            source: source
        )
        controller.startTestSession(for: context)
        return controller
    }

    /// Regression: a `.paste` dismisses the popup and `hide()` clears the session. Policy must be captured before that hide, or the Terminal escape hatch pastes instead of copying.
    @MainActor
    func testDeliverResultAppliesDenyPasteDespiteDismissingHide() async throws {
        let handler = RecordingHandler()
        // Probe would happily paste; the denyPaste policy alone must force a copy.
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: AppPolicyContext(denyPaste: true))
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// A nil delivery context (explicit user request, e.g. the AI card's Paste button) is never re-decided, even if the probe says paste is unavailable.
    @MainActor
    func testNilDeliveryPassesPasteThroughUntouched() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.handleActionResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    // MARK: - Implicit .text delivery wiring (defaults preserved)

    /// Default primary = paste: an implicit `.text` result pastes and dismisses, as the string-return behavior does.
    @MainActor
    func testTextDeliversPasteAndDismissesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
        XCTAssertFalse(controller.isVisible, "a .text result with a paste preference must dismiss like a paste today")
    }

    /// Default primary = paste + cannot paste → copy with the default "Copied" toast.
    @MainActor
    func testTextDeliversCopyAndCopiedToastWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
    }

    /// User picks copy for the primary click: `.text` delivers a copy with the default Copied toast and dismisses.
    @MainActor
    func testTextDeliversCopyWhenPreferenceIsCopy() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.pendingActionRecommendedResult = .copy
        controller.pendingActionOutputKind = .text
        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
    }

    /// A secondary click with the default secondary = copy: `.text` copies without a toast.
    @MainActor
    func testTextSecondaryCopiesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let stub = TextStubAction()
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertFalse(controller.isVisible)
    }

    @MainActor
    func testOCRDirectSecondaryCutIsCopied() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default, source: .ocr)
        defer { controller.hide() }

        controller.runAction(TextStubAction(result: .cut("recognized")), with: controllerCurrentContext(controller, source: .ocr), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("recognized"))
    }

    @MainActor
    func testOCRDirectSimulatePasteIsDropped() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default, source: .ocr)
        defer { controller.hide() }

        controller.runAction(TextStubAction(result: .simulatePaste), with: controllerCurrentContext(controller, source: .ocr), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .none)
    }

    @MainActor
    func testOCRDeclaredSecondarySequenceAndLoadingResultAreNormalized() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default, source: .ocr)
        defer { controller.hide() }

        let action = TextStubAction(
            result: .success,
            delivery: ActionDelivery(secondary: .sequence([.cut("one"), .simulatePaste, .copy("two")]))
        )
        controller.runAction(action, with: controllerCurrentContext(controller, source: .ocr), isSecondaryClick: true)
        assertCase(try await awaitDelivery(at: 0, from: handler), .copy("one"))
        assertCase(try await awaitDelivery(at: 1, from: handler), .none)
        assertCase(try await awaitDelivery(at: 2, from: handler), .copy("two"))

        let loadingController = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default, source: .ocr)
        defer { loadingController.hide() }
        loadingController.runLoadingAction(SlowResultStubAction(result: .cut("loaded")), with: controllerCurrentContext(loadingController, source: .ocr), isSecondaryClick: false)
        assertCase(try await awaitDelivery(at: 3, from: handler), .copy("loaded"))
    }

    // MARK: - Builtin explicit paste/copy never governed by the picker (controller level)

    /// Builtins author explicit outcomes; an explicit `.paste` is delivered as authored and dismisses, never routed to the AI card.
    @MainActor
    func testExplicitPasteDeliversNotPreviewedWithPreviewPreference() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }

        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text
        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
        XCTAssertFalse(controller.isVisible, "an explicit paste must dismiss like a paste today")
        XCTAssertEqual(controller.modeStore.mode, .actions, "an explicit paste must never open the preview card")
        XCTAssertNil(controller.modeStore.resultCard)
    }

    /// An explicit `.copy` with a `.preview` preference stays a copy with the default Copied toast (no card).
    @MainActor
    func testExplicitCopyDeliversNotPreviewedWithPreviewPreference() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text
        controller.deliverResult(.copy("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
        XCTAssertEqual(controller.modeStore.mode, .actions, "an explicit copy must never open the preview card")
    }

    // MARK: - Preview routing (implicit .text → AI result card)

    /// Preview preference on a primary click keeps the popup open and renders the text in the AI result card; no effect is delivered.
    @MainActor
    func testTextPreviewKeepsPopupOpenAndShowsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"
        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(handler.results.isEmpty, "preview must not deliver any effect")
        XCTAssertTrue(controller.isVisible, "preview keeps the popup open")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "hello")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "My Action")
        XCTAssertFalse(controller.modeStore.resultCard?.isError ?? true)
    }

    /// Preview with cannot-paste hides the card's Paste button (modeStore.canPaste == false).
    @MainActor
    func testTextPreviewHidesPasteWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"
        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.canPaste != false && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(controller.modeStore.canPaste, false, "preview card must gate Paste on the probe answer")
    }

    /// Preview with can-paste keeps Paste visible on the card.
    @MainActor
    func testTextPreviewKeepsPasteWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"
        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.canPaste == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertNotNil(controller.modeStore.canPaste, "preview card must resolve paste availability before rendering")
        XCTAssertNotEqual(controller.modeStore.canPaste, false)
    }

    /// Esc collapses the preview card back to the actions bar (exitContent) without hiding the popup.
    @MainActor
    func testTextPreviewEscCollapsesToBar() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"
        controller.pendingActionRecommendedResult = .preview
        controller.pendingActionOutputKind = .text

        controller.deliverResult(.text("hello"))

        var deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        controller.exitContent()

        deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .actions && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.resultCard)
        XCTAssertTrue(controller.isVisible, "collapsing the card never hides the popup")
    }

    /// A loading action with preview preference: the spinner hides and the popup re-shows as a
    /// content-mode card using the original selection.
    @MainActor
    func testLoadingTextPreviewReshowsPopupAsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowTextStubAction(text: "loaded", recommendedResult: .preview), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        XCTAssertFalse(toast.isLoading, "the spinner must hide when the preview card re-shows")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "loaded")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Slow Text")
        XCTAssertTrue(controller.isVisible, "the popup must re-show as the preview card")
        XCTAssertTrue(handler.results.isEmpty)
    }

    /// A loading action with a paste preference keeps the existing settle path (deliver + spinner
    /// swap/hide) — no re-show.
    @MainActor
    func testLoadingTextPastePreferenceDeliversNormally() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.runLoadingAction(SlowTextStubAction(text: "loaded"), with: controllerCurrentContext(controller), isSecondaryClick: false)

        assertCase(try await awaitDelivery(from: handler), .paste("loaded"))
    }

    // MARK: - Preview routing review follow-ups (declared secondary + pending-state leak)

    /// A declared secondary beats the picker even for `.text` with a preview preference: the popup must dismiss with the declared outcome.
    @MainActor
    func testTextPreviewWithDeclaredSecondaryDismisses() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         settingsStore: store)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .openURL(url)), performResult: .text("a"), recommendedResult: .preview)
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        XCTAssertFalse(controller.isVisible, "a dismissing declared secondary must dismiss even when the raw .text preference is preview")
    }

    /// The right-click path snapshots the declared delivery into its own context and must not leave pending state for a later completion paste to reuse.
    @MainActor
    func testRunActionPreviewDoesNotLeakDeclaredDeliveryOntoCompletionPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast,
                                         settingsStore: store)
        defer { controller.hide(); toast.hide() }

        let declared = StatusFeedback(message: "Saved", style: .info)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(primaryToast: declared), performResult: .text("a"), recommendedResult: .preview)
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: false)

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Declared", "the preview card must show the performing action's title")
        XCTAssertNil(controller.pendingActionTitle, "runAction must not leave pendingActionTitle behind")
        XCTAssertNil(controller.pendingDelivery, "runAction must not leave pendingDelivery behind")

        controller.deliverResult(.paste("word"))

        assertCase(try await awaitDelivery(from: handler), .paste("word"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(toast.currentFeedback, "the completion paste must not fire a stale declared toast")
    }

    /// Left-click + probe says cannot paste → copy.
    @MainActor
    func testDeliverResultCopiesWhenProbeSaysCannotPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// Left-click + probe says paste is available → paste (positive control through the full wiring).
    @MainActor
    func testDeliverResultPastesWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    // MARK: - Toast routing: paste→copy downgrade shows "Copied"; native copy shows nothing

    /// A `.paste` downgraded to `.copy` surfaces the "Copied" toast, independent of the popup.
    @MainActor
    func testDowngradeToCopyShowsCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
        XCTAssertEqual(toast.currentFeedback?.style, .success)
    }

    /// When resultHandler.handle throws an error, the "Copied" success toast is NOT shown (an error status is shown instead).
    @MainActor
    func testDeliveryFailureDoesNotShowCopiedToast() async throws {
        let handler = FailingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while toast.currentFeedback == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertNotEqual(toast.currentFeedback?.message, String(localized: "Copied"))
        XCTAssertEqual(toast.currentFeedback?.style, .error)
    }

    /// A native `.copy` result delivers the default Copied toast.
    @MainActor
    func testNativeCopyShowsCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.copy("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback?.message, String(localized: "Copied"))
    }

    /// Every `.toast` routes to the toast surface; with no panel, the toast uses cursor-relative placement.
    @MainActor
    func testToastRoutesToToast() async throws {
        let toast = ToastPanelController()
        let controller = shownController(resultHandler: RecordingHandler(),
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }
        controller.handleActionResult(.toast(StatusFeedback(message: "hello", style: .info)))
        XCTAssertEqual(toast.currentFeedback?.message, "hello")
        XCTAssertTrue(toast.isShowing)
        XCTAssertNil(toast.lastAnchorFrame, "no panel frame exists in a test session; must not invent a cursor anchor")
    }

    /// An auto-dismissing toast holds while hovered; dismissible toasts accept pointer events so hover can fire.
    @MainActor
    func testToastHoverSuspendsAutoDismissal() async throws {
        let toast = ToastPanelController(autoDismissNanoseconds: 80_000_000)
        toast.show(StatusFeedback(message: "hello", style: .info))
        XCTAssertTrue(toast.isShowing)
        XCTAssertTrue(toast.hasPendingDismissal, "a dismissible toast must schedule its dismissal")
        XCTAssertFalse(toast.panelIgnoresMouseEvents, "a dismissible toast must accept pointer events to track hover")

        toast.handleHover(true)
        XCTAssertFalse(toast.hasPendingDismissal, "hovering must pause the pending dismissal")

        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(toast.isShowing, "a hovered toast must stay past its auto-dismiss window")

        // Its window elapsed while hovered, so leaving hides it at once rather than granting a fresh one.
        toast.handleHover(false)
        XCTAssertFalse(toast.isShowing, "a toast whose window elapsed must hide immediately on pointer exit")
        XCTAssertFalse(toast.hasPendingDismissal)
    }

    /// Leaving before the window elapses keeps the toast up and it still auto-dismisses.
    @MainActor
    func testToastHoverResumesAndDismisses() async throws {
        let toast = ToastPanelController(autoDismissNanoseconds: 120_000_000)
        toast.show(StatusFeedback(message: "hello", style: .info))

        toast.handleHover(true)
        try await Task.sleep(nanoseconds: 40_000_000)
        toast.handleHover(false)
        XCTAssertTrue(toast.hasPendingDismissal, "leaving before the deadline must reschedule the dismissal")

        let deadline = Date().addingTimeInterval(3.0)
        while toast.isShowing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(toast.isShowing, "the toast must still auto-dismiss after the cursor leaves")
    }

    // MARK: - Loading (slow-action) early-close flow

    /// A `showsLoading` action closes the popup, shows a spinner, and fades the toast when the result lands with no description.
    @MainActor
    func testLoadingActionShowsSpinnerThenFades() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        await awaitLoadingFade(toast: toast)
        XCTAssertFalse(toast.isLoading, "loading toast should fade once a description-free result lands")
    }

    @MainActor
    private func controllerCurrentContext(_ controller: PopupWindowController, source: SelectionSource = .selection) -> ActionContext {
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default,
            source: source
        )
        return ActionContext(selection: context, modifiers: [])
    }

    /// A loading action's explicit `loadingMessage` is shown verbatim, not the default "Opening <title>…" text.
    @MainActor
    func testLoadingActionUsesCustomLoadingMessage() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(MessageStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        XCTAssertEqual(toast.currentFeedback?.message, "Connecting to Music…")
        await awaitLoadingFade(toast: toast)
        XCTAssertFalse(toast.isLoading, "loading toast should fade once a description-free result lands")
    }

    /// A settled keep-visible toast must still auto-dismiss, since the popup was closed when loading started.
    @MainActor
    func testLoadingActionKeepVisibleToastAutoDismisses() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 30_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(KeepVisibleToastLoadingAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        await awaitLoadingFade(toast: toast)
        XCTAssertEqual(toast.currentFeedback?.message, "Formatted")
        XCTAssertFalse(toast.isLoading)
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isShowing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertFalse(toast.isShowing, "settled loading toast with keepVisible: true must auto-dismiss")
    }

    /// Hiding the popup controller must dismiss any keep-visible toast currently showing.
    @MainActor
    func testHideDismissesKeepVisibleToast() async throws {
        let toast = ToastPanelController()
        let controller = shownController(resultHandler: RecordingHandler(),
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        controller.handleActionResult(.toast(StatusFeedback(message: "Pinned", style: .info, keepVisible: true)))
        XCTAssertTrue(toast.isShowing)
        controller.hide()
        XCTAssertFalse(toast.isShowing, "hide() must dismiss any keepVisible toast")
    }

    /// Cancel while loading cancels the task and hides the toast without an error banner.
    @MainActor
    func testLoadingActionCancellationDismissesToastWithoutError() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowStubAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")

        // Cancel the active tasks (same callback triggered when user clicks the loading toast)
        controller.cancelActiveTasks()

        XCTAssertFalse(toast.isLoading, "toast should immediately stop loading")
        XCTAssertFalse(toast.isShowing, "toast should be hidden")
        XCTAssertNil(controller.activeLoadingTask, "activeLoadingTask must be nil after cancellation")

        // Wait slightly to ensure no error toast or result leaks
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(toast.currentFeedback, "no error toast should be surfaced on cancellation")
        XCTAssertTrue(handler.results.isEmpty, "no result should be delivered")
    }

    // MARK: - Secondary-click threading: runAction must propagate the click intent into the action context

    /// A secondary click must reach `perform` as `isSecondaryClick == true`, so Define copies instead of opening Dictionary.
    @MainActor
    func testRunActionThreadsSecondaryClickIntoActionContext() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: true)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, true, "secondary click must reach the action context")
    }

    /// A normal primary click must reach `perform` as `context.isSecondaryClick == false` (default).
    @MainActor
    func testRunActionDefaultsSecondaryClickToFalse() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: false)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, false, "primary click must not set isSecondaryClick")
    }

    // MARK: - Explicit click intent: the palette's keyboard secondary reaches the delivery snapshot

    /// Regression: the palette's keyboard secondary signals via its own `replace` flag, not `pendingClickIntent`, so the intent is passed explicitly into the snapshot.
    @MainActor
    func testExplicitSecondaryIntentSnapshotCopiesPasteResult() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let stub = DeclaredDeliveryStub(delivery: .none)
        let snapshot = controller.deliverySnapshot(for: stub, clickIntent: .secondary)
        XCTAssertEqual(snapshot.clickIntent, .secondary,
                       "the explicit intent must win over the pending mouse intent")

        // Model the fixed palette path: snapshot with the explicit intent, then deliver.
        controller.inFlightDeliveryContext = snapshot
        controller.deliverResult(.paste("word"))

        assertCase(try await awaitDelivery(from: handler), .copy("word"),
                   "a keyboard secondary run must deliver a paste primary as a copy")
    }

    // MARK: - Declared delivery wiring: runAction must snapshot the action's delivery and render its toast

    /// A declared secondary outcome and toast: a right-click perform delivers the declared secondary and surfaces its toast.
    @MainActor
    func testRunActionDeliversDeclaredSecondaryAndToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let url = URL(string: "https://alt")!
        let declared = StatusFeedback(message: "Copied alt", style: .success)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .openURL(url), secondaryToast: declared))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        XCTAssertEqual(toast.currentFeedback, declared, "the declared secondary toast must surface for a secondary click")
    }

    /// A declared primary toast surfaces even for a description-free `.success` (not tied to a paste→copy downgrade).
    @MainActor
    func testRunActionShowsDeclaredPrimaryToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let declared = StatusFeedback(message: "Saved", style: .info)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(primaryToast: declared), performResult: .success)
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: false)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback, declared, "the declared primary toast must surface for a primary click")
    }

    // MARK: - Single-use declared delivery: a completion paste must not reuse a prior action's declaration

    /// A completion paste after a prior action's `.toast` dismissal carries no declared secondary and fires no stale toast; the declaration is consumed on delivery.
    @MainActor
    func testStaleDeclaredDeliveryDoesNotLeakOntoCompletionPaste() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let working = StatusFeedback(message: "working", style: .info)
        let declared = StatusFeedback(message: "Saved", style: .info)
        controller.pendingDelivery = ActionDelivery(secondary: .paste("alt"), primaryToast: declared)
        controller.deliverResult(.toast(working))
        await awaitToastMessage(toast, "working")

        controller.deliverResult(.paste("word"))

        assertCase(try await awaitDelivery(from: handler), .paste("word"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(toast.currentFeedback, working,
                       "the prior action's declared delivery must not leak: the completion paste fires no stale toast")
    }

    // MARK: - One toast per run: a script toast wins over the delivery companion

    /// A script toast suppresses the delivery companion toast: a declared primary toast must not surface for a `.copy` effect (one toast per run).
    @MainActor
    func testScriptToastWinsOverDeclaredToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "saved", style: .info)
        controller.pendingDelivery = ActionDelivery(primaryToast: StatusFeedback(message: "declared", style: .info))
        controller.deliverResult(.sequence([.toast(scriptToast), .copy("x")]))

        assertCase(try await awaitDelivery(from: handler), .copy("x"))
        XCTAssertEqual(toast.currentFeedback, scriptToast,
                       "the script toast must win over the declared delivery companion")
    }

    /// Same rule for the paste→copy downgrade: its default "Copied" toast must not show alongside a script toast.
    @MainActor
    func testScriptToastSuppressesDefaultCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "saved", style: .info)
        controller.deliverResult(.sequence([.toast(scriptToast), .paste("x")]))

        assertCase(try await awaitDelivery(from: handler), .copy("x"))
        XCTAssertEqual(toast.currentFeedback, scriptToast,
                       "the script toast must win over the default Copied toast")
    }

    @MainActor
    func testSequenceItemsRunInOrderWhenPasteProbeSuspends() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: DelayedProbe(result: true, delayNanoseconds: 50_000_000),
                                         appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.sequence([.paste("a"), .copy("b")]))

        let deadline = Date().addingTimeInterval(3.0)
        while handler.results.count < 2 && Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(handler.results.count, 2)
        assertCase(handler.results[0], .paste("a"))
        assertCase(handler.results[1], .copy("b"))
    }

    /// A declared secondary replaces a sequence once; walking leaves with the same context would run it per item.
    @MainActor
    func testDeclaredSecondaryOnSequenceExecutesOnce() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .openURL(url)),
            performResult: .sequence([.paste("a"), .paste("b")])
        )
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 1, "declared secondary must run once, not once per sequence leaf")
    }

    /// Same single-use rule on the loading settle path.
    @MainActor
    func testDeclaredSecondaryOnLoadingSequenceExecutesOnce() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .openURL(url)),
            performResult: .sequence([.paste("a"), .paste("b")]),
            showsLoading: true
        )
        controller.runLoadingAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 1, "declared secondary must run once on the loading sequence path")
    }

    /// A declared `.sequence` secondary must not recurse; the nested walk clears the declaration and runs items in order.
    @MainActor
    func testDeclaredSequenceSecondaryDoesNotRecurse() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .sequence([.copy("x"), .openURL(url)])),
            performResult: .sequence([.paste("a")])
        )
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("x"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 2, "a declared sequence secondary must run its items once")
        assertCase(handler.results[1], .openURL(url))
    }

    // MARK: - Greptile review regression tests: feedback preservation & declared sequence paste

    /// Suppression must follow the outcome that actually runs: a declared secondary's toast is not suppressed by a discarded primary toast.
    @MainActor
    func testDiscardedPrimarySequenceToastDoesNotSuppressDeclaredSecondaryToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "discarded", style: .info)
        let secondaryToast = StatusFeedback(message: "declared secondary feedback", style: .success)
        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .openURL(url), secondaryToast: secondaryToast),
            performResult: .sequence([.toast(scriptToast), .paste("primary")])
        )
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        await awaitToastMessage(toast, "declared secondary feedback")
        XCTAssertEqual(toast.currentFeedback, secondaryToast,
                       "the declared secondary toast must not be suppressed by the discarded primary sequence toast")
    }

    /// Loading path: a secondary replacing a toast-containing sequence with an outcome lacking a companion toast must still fade the spinner.
    @MainActor
    func testDiscardedPrimarySequenceToastDoesNotLeaveLoadingSpinnerOnSecondaryClick() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "discarded", style: .info)
        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .openURL(url)),
            performResult: .sequence([.toast(scriptToast), .paste("primary")]),
            showsLoading: true
        )
        controller.runLoadingAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        await awaitLoadingFade(toast: toast)
        XCTAssertFalse(toast.isLoading, "the loading indicator must fade when the running outcome has no companion toast")
    }

    /// Loading path: the spinner transitions to the declared `secondaryToast` of the replacing outcome.
    @MainActor
    func testDiscardedPrimarySequenceToastPreservesDeclaredSecondaryToastOnLoading() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let scriptToast = StatusFeedback(message: "discarded", style: .info)
        let secondaryToast = StatusFeedback(message: "loading secondary feedback", style: .success)
        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .openURL(url), secondaryToast: secondaryToast),
            performResult: .sequence([.toast(scriptToast), .paste("primary")]),
            showsLoading: true
        )
        controller.runLoadingAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        await awaitToastMessage(toast, "loading secondary feedback")
        XCTAssertEqual(toast.currentFeedback, secondaryToast,
                       "the declared secondary toast must surface for loading action secondary click")
    }

    /// A declared secondary sequence containing `.paste` keeps the `.paste` when the target can paste (not converted to `.copy`).
    @MainActor
    func testDeclaredSequenceSecondaryPastesWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .sequence([.paste("declared_paste"), .openURL(url)])),
            performResult: .sequence([.copy("a")])
        )
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .paste("declared_paste"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 2)
        assertCase(handler.results[1], .openURL(url))
    }

    /// If the target cannot paste, the probe still downgrades a declared sequence's `.paste` to `.copy`.
    @MainActor
    func testDeclaredSequenceSecondaryDowngradesToCopyWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .sequence([.paste("declared_paste"), .openURL(url)])),
            performResult: .sequence([.copy("a")])
        )
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("declared_paste"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 2)
        assertCase(handler.results[1], .openURL(url))
    }

    /// Loading path: a declared secondary sequence's `.paste` is also preserved when paste is available.
    @MainActor
    func testDeclaredLoadingSequenceSecondaryPastesWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)
        defer { controller.hide(); toast.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(
            delivery: ActionDelivery(secondary: .sequence([.paste("declared_paste"), .openURL(url)])),
            performResult: .sequence([.copy("a")]),
            showsLoading: true
        )
        controller.runLoadingAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .paste("declared_paste"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(handler.results.count, 2)
        assertCase(handler.results[1], .openURL(url))
    }

    // MARK: - Declared .paste secondary probes even on a secondary click


    /// A declared `.paste` secondary on a secondary click still runs the probe; with paste available it is delivered as a paste.
    @MainActor
    func testDeclaredPasteSecondaryPastesOnSecondaryClickWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default)
        defer { controller.hide() }

        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .paste("alt")))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .paste("alt"))
    }

    /// Same declared `.paste` secondary, target cannot paste: the probe downgrades it to copy, never pastes blindly.
    @MainActor
    func testDeclaredPasteSecondaryDowngradesToCopyWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: false),
                                         appPolicy: .default)
        defer { controller.hide() }

        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .paste("alt")))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("alt"))
    }

    // MARK: - Builtin delivery declarations (uniform with extension actions)

    /// DefineAction relies on the default nil delivery: delivery is fully picker-governed.
    func testDefineDeclaresNoDelivery() {
        XCTAssertNil(DefineAction().delivery,
                     "DefineAction must rely on the default nil delivery (picker-governed)")
    }

    /// PasteAction uses the default nil delivery; the resolver derives `.copy` for a secondary click.
    func testPasteDeclaresNoDelivery() {
        XCTAssertNil(PasteAction().delivery,
                     "PasteAction must rely on the default nil delivery (paste→copy default)")
    }

    @MainActor
    func testAsyncActionCompletingAfterHidePreservesDeliveryPolicyAndContext() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: AppPolicyContext(denyPaste: true))
        let action = SlowPasteStubAction(text: "delayed")
        let context = controller.currentActionContext!

        controller.runAction(action, with: context, isSecondaryClick: false)
        // Dismiss popup while action is executing
        controller.hide()

        let delivered = try await awaitDelivery(from: handler)
        // Must still be .copy because the snapshotted policy had denyPaste, even though hide() was called
        assertCase(delivered, .copy("delayed"))
    }

    @MainActor
    func testAsyncActionDowngradesPasteToCopyWhenTargetAppIsNoLongerActive() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)

        let targetApp = NSWorkspace.shared.runningApplications.first!
        controller.previousFrontmostApp = targetApp

        // When action completes, frontmost application is different (user switched apps)
        let otherApp = NSWorkspace.shared.runningApplications.first { $0.processIdentifier != targetApp.processIdentifier }!
        controller.frontmostApplicationProvider = { otherApp }

        let action = SlowPasteStubAction(text: "unsafe paste")
        let context = controllerCurrentContext(controller)

        controller.runAction(action, with: context, isSecondaryClick: false)

        let delivered = try await awaitDelivery(from: handler)
        // Must downgrade to .copy to avoid pasting into the wrong application
        assertCase(delivered, .copy("unsafe paste"))
        await awaitToastMessage(toast, String(localized: "Copied"))
    }

    @MainActor
    func testFieldChangeBeforeAsyncActionFinishesCopiesInsteadOfPasting() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler, pasteProbe: FixedProbe(result: true), appPolicy: .default)
        let target = DeliveryTestApp(pid: 90001)
        controller.previousFrontmostApp = target
        controller.frontmostApplicationProvider = { target }
        var fieldIsCurrent = true
        controller.selectionIsCurrent = { _ in fieldIsCurrent }
        controller.runAction(SlowPasteStubAction(text: "late result"),
                             with: controllerCurrentContext(controller), isSecondaryClick: false)
        fieldIsCurrent = false
        assertCase(try await awaitDelivery(from: handler), .copy("late result"))
        XCTAssertEqual(controller.lastDeliveryStatus, .targetChanged)
    }

    @MainActor
    func testStaleEditableSelectionIsRejectedBeforeActionRuns() {
        let handler = RecordingHandler()
        let controller = PopupWindowController(
            resultHandler: handler,
            pasteProbe: FixedProbe(result: true),
            settingsStore: MemorySettingsStore()
        )
        let selection = SelectionContext(
            text: "word",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default,
            selectionGeneration: 7,
            isEditable: true
        )
        controller.startTestSession(for: selection)
        controller.selectionIsCurrent = { _ in false }
        let action = KeyPressAction(
            id: "com.test.bold",
            title: "Bold",
            spec: KeyPressSpec(manifestString: "command+b")!,
            chrome: ActionChrome(requiresLiveSelection: true),
            rules: ExtensionActionRules(requirements: ActionRequirements(input: .editableSelection))
        )

        controller.runAction(action, with: controller.currentActionContext!, isSecondaryClick: false)
        XCTAssertTrue(handler.results.isEmpty)
        controller.hide()
    }

    @MainActor
    func testRequiredPasteTargetResultIsDroppedAfterTargetApplicationSwitches() async throws {
        let handler = RecordingHandler()
        let probe = SwitchingTargetProbe()
        let controller = PopupWindowController(
            resultHandler: handler,
            pasteProbe: probe,
            settingsStore: MemorySettingsStore()
        )
        let target = DeliveryTestApp(pid: 90001)
        let other = DeliveryTestApp(pid: 90002)
        controller.previousFrontmostApp = target
        controller.frontmostApplicationProvider = { probe.switched ? other : target }
        controller.startTestSession(for: SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            appPolicy: .default
        ), pasteAvailable: true)
        let action = SlowResultStubAction(
            result: .paste("stale destination"),
            rules: ExtensionActionRules(requirements: ActionRequirements(input: .optional, requiresPasteTarget: true))
        )

        controller.runAction(action, with: controller.currentActionContext!, isSecondaryClick: false)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(probe.switched, "the result should wait for its paste probe")
        XCTAssertTrue(handler.results.isEmpty, "a destination-bound action result must not dispatch after its target app changes during the probe")
        controller.hide()
    }

    @MainActor
    func testFieldChangeWhilePasteProbeSuspendsCopiesInsteadOfPasting() async throws {
        let handler = RecordingHandler()
        let probe = SwitchingTargetProbe()
        let controller = shownController(resultHandler: handler, pasteProbe: probe, appPolicy: .default)
        let target = DeliveryTestApp(pid: 90001)
        controller.previousFrontmostApp = target
        controller.frontmostApplicationProvider = { target }
        controller.selectionIsCurrent = { _ in !probe.switched }
        controller.deliverResult(.paste("late result"))
        assertCase(try await awaitDelivery(from: handler), .copy("late result"))
        XCTAssertEqual(controller.lastDeliveryStatus, .targetChanged)
    }

    @MainActor
    func testAppSwitchWhilePasteProbeSuspendsDowngradesToCopy() async throws {
        let handler = RecordingHandler()
        let probe = SwitchingTargetProbe()
        let controller = shownController(resultHandler: handler, pasteProbe: probe, appPolicy: .default)
        let target = DeliveryTestApp(pid: 90001)
        let other = DeliveryTestApp(pid: 90002)
        controller.previousFrontmostApp = target
        controller.frontmostApplicationProvider = { probe.switched ? other : target }
        controller.deliverResult(.paste("safe text"))
        assertCase(try await awaitDelivery(from: handler), .copy("safe text"))
    }

    @MainActor
    func testDeliverResultAfterHidePreservesPrecapturedInFlightDeliveryContext() async throws {
        let handler = RecordingHandler()
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: AppPolicyContext(denyPaste: true))
        let stub = SlowPasteStubAction(text: "will copy")

        // Simulate onWillPerformAction firing before async perform
        controller.inFlightDeliveryContext = controller.deliverySnapshot(for: stub)

        // User switches windows or clicks outside -> hide() clears live session
        controller.hide()
        XCTAssertNil(controller.currentActionContext, "hide() must clear live context")

        // Action completes later and calls deliverResult
        controller.deliverResult(.paste("will copy"))

        // Must still be .copy because inFlightDeliveryContext preserved the denyPaste policy
        assertCase(try await awaitDelivery(from: handler), .copy("will copy"))
    }

    @MainActor
    func testDeliverResultAfterHideDowngradesToCopyWhenTargetAppChanged() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = shownController(resultHandler: handler,
                                         pasteProbe: FixedProbe(result: true),
                                         appPolicy: .default,
                                         toastController: toast)

        let targetApp = NSWorkspace.shared.runningApplications.first!
        controller.previousFrontmostApp = targetApp
        let stub = SlowPasteStubAction(text: "safe copy")

        controller.inFlightDeliveryContext = controller.deliverySnapshot(for: stub)

        // User switches to another application
        let otherApp = NSWorkspace.shared.runningApplications.first { $0.processIdentifier != targetApp.processIdentifier }!
        controller.frontmostApplicationProvider = { otherApp }

        controller.hide()

        // Action completes
        controller.deliverResult(.paste("safe copy"))

        assertCase(try await awaitDelivery(from: handler), .copy("safe copy"))
        await awaitToastMessage(toast, String(localized: "Copied"))
    }
}

/// A slow action returning `.paste` after a short delay to model asynchronous background execution.
private final class SlowPasteStubAction: Action, @unchecked Sendable {
    let id = "stub.slowpaste"
    let title = "Slow Paste"
    let icon: ActionIcon = .symbol("sparkles")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let text: String
    init(text: String = "loaded paste") { self.text = text }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .paste(text)
    }
}

/// Records every effect the handler is asked to deliver; main-actor isolated like the `ActionResultHandler` protocol.
@MainActor
private final class RecordingHandler: ActionResultHandler, Sendable {
    private(set) var results: [ActionResult] = []

    func handle(_ result: ActionResult, in view: NSView?) async throws {
        results.append(result)
    }

    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {
        results.append(result)
    }
}

@MainActor
private final class FailingHandler: ActionResultHandler, Sendable {
    struct TestError: LocalizedError {
        var errorDescription: String? { "Delivery failed" }
    }
    func handle(_ result: ActionResult, in view: NSView?) async throws {
        throw TestError()
    }
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {}
}

private struct FixedProbe: PasteAvailabilityProbing {
    let result: Bool?

    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        result
    }
}

private struct DelayedProbe: PasteAvailabilityProbing {
    let result: Bool?
    let delayNanoseconds: UInt64

    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return result
    }
}

/// A `showsLoading` action resolving after a delay to a description-free `.success` (like an empty-stdout AppleScript).
private final class SlowStubAction: Action {
    let id = "stub.slow"
    let title = "Slow"
    let icon: ActionIcon = .symbol("play")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .success
    }
}

/// A `showsLoading` action that declares its own loading toast text.
private final class MessageStubAction: Action {
    let id = "stub.message"
    let title = "Slow"
    let icon: ActionIcon = .symbol("play")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true, loadingMessage: "Connecting to Music…") }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .success
    }
}

/// A `showsLoading` action that returns a toast with `keepVisible: true`.
private final class KeepVisibleToastLoadingAction: Action {
    let id = "stub.keepvisible"
    let title = "Format"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 20_000_000)
        return .toast(StatusFeedback(message: "Formatted", style: .success, keepVisible: true))
    }
}

/// Records the `ActionContext` passed to `perform` so tests can assert click intent; lock-protected so the Sendable conformance stays race-free.
private final class SecondaryClickProbeAction: Action, @unchecked Sendable {
    let id = "stub.secondary"
    let title = "SecondaryClickProbe"
    let icon: ActionIcon = .symbol("hand.point.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let captured = LockedContextBox()
    var lastPerformContext: ActionContext? { captured.value }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        captured.set(context)
        return .copyDefinition(context.selection.text)
    }
}

/// Declares a `delivery` (secondary outcome + per-click toasts); `performResult` lets tests exercise non-paste results.
private final class DeclaredDeliveryStub: Action, @unchecked Sendable {
    let id = "stub.declared"
    let title = "Declared"
    let icon: ActionIcon = .symbol("arrow.turn.down.right")
    let recommendedResult: ActionResultDeliveryMode?
    private let showsLoading: Bool
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: showsLoading, outputKind: .text, recommendedResult: recommendedResult) }
    var delivery: ActionDelivery? { declaredDelivery }
    private let declaredDelivery: ActionDelivery
    let performResult: ActionResult
    init(delivery: ActionDelivery, performResult: ActionResult = .paste("hello"), recommendedResult: ActionResultDeliveryMode? = nil, showsLoading: Bool = false) {
        self.declaredDelivery = delivery
        self.performResult = performResult
        self.recommendedResult = recommendedResult
        self.showsLoading = showsLoading
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { performResult }
}

/// Returns implicit `.text`, like JS string returns, AppleScript output, shell stdout, and text snippets.
private final class TextStubAction: Action, @unchecked Sendable {
    let id = "stub.text"
    let title = "Text Action"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let deliveryValue: ActionDelivery?
    private let result: ActionResult
    init(result: ActionResult = .text("hello"), delivery: ActionDelivery = .none) {
        self.result = result
        self.deliveryValue = delivery.secondary == nil && delivery.primaryToast == nil && delivery.secondaryToast == nil
            ? nil
            : delivery
    }
    var delivery: ActionDelivery? { deliveryValue }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { result }
}

private final class SlowResultStubAction: ActionWithRules, @unchecked Sendable {
    let id = "stub.slowresult"
    let title = "Slow Result"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    private let result: ActionResult
    let rules: ExtensionActionRules?
    init(result: ActionResult, rules: ExtensionActionRules? = nil) {
        self.result = result
        self.rules = rules
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return result
    }
}

/// A `showsLoading` action returning `.text` after a short delay (loading + preview re-show path).
private final class SlowTextStubAction: Action, @unchecked Sendable {
    let id = "stub.slowtext"
    let title = "Slow Text"
    let icon: ActionIcon = .symbol("text.alignleft")
    let recommendedResult: ActionResultDeliveryMode?
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true, outputKind: .text, recommendedResult: recommendedResult) }
    private let text: String
    init(text: String = "loaded", recommendedResult: ActionResultDeliveryMode? = nil) {
        self.text = text
        self.recommendedResult = recommendedResult
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .text(text)
    }
}

/// Lock-protected capture of the context an action performed with; synchronous so it is callable from async `perform`.
private final class LockedContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ActionContext?
    func set(_ value: ActionContext) {
        lock.lock(); defer { lock.unlock() }
        storage = value
    }
    var value: ActionContext? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

@MainActor
private final class SwitchingTargetProbe: PasteAvailabilityProbing {
    var switched = false
    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        await Task.yield()
        switched = true
        return true
    }
}

private final class DeliveryTestApp: NSRunningApplication {
    private let pid: pid_t
    init(pid: pid_t) { self.pid = pid; super.init() }
    override var processIdentifier: pid_t { pid }
    override var bundleIdentifier: String? { "com.test.delivery" }
}
