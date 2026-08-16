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
        case (.success, .success), (.none, .none): XCTAssertTrue(true, message, file: file, line: line)
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

    // MARK: - Toast

    func testDefaultCopiedToastOnDerivedCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .secondary, canPaste: true, delivery: .none)
        XCTAssertEqual(toast?.message, "Copied")
        XCTAssertEqual(toast?.style, .success)
    }

    func testNoDefaultToastOnHonoredPaste() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .paste("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertNil(toast)
    }

    func testNoDefaultToastOnNativeCopy() {
        let (_, toast) = ActionResultDelivery.resolve(raw: .copy("a"), clickIntent: .primary, canPaste: true, delivery: .none)
        XCTAssertNil(toast)
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
        XCTAssertEqual(toast?.message, "Copied", "a paste context delivered as a copy fires the default Copied toast")
    }

    func testTextWithCopyPreferenceCopiesWithoutToast() {
        let (r, toast) = ActionResultDelivery.resolve(raw: .text("hello"), clickIntent: .primary, canPaste: true, delivery: .none, preference: .copy)
        assertCase(r, .copy("hello"))
        XCTAssertNil(toast, "a native copy fires no companion toast")
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
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(handler.results.isEmpty, "effect delivery never reached the handler")
        return handler.results.first!
    }

    /// Polls `toast.isLoading` until it flips false (the loading toast fades once the action's
    /// result lands) or the deadline passes — a state-based wait instead of a fixed sleep, so the
    /// assertion isn't flaky on slow machines.
    @MainActor
    private func awaitLoadingFade(toast: ToastPanelController) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Polls the toast until it shows `message` or the deadline passes — waits for an action's
    /// async `perform` to settle a `.toast` before the test proceeds.
    @MainActor
    private func awaitToastMessage(_ toast: ToastPanelController, _ message: String) async {
        let deadline = Date().addingTimeInterval(3.0)
        while toast.currentFeedback?.message != message && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    private func shownController(resultHandler: ActionResultHandler,
                                 pasteProbe: PasteAvailabilityProbing,
                                 appPolicy: AppPolicyContext,
                                 toastController: ToastPanelController = ToastPanelController(),
                                 settingsStore: SettingsStore = MemorySettingsStore()) throws -> PopupWindowController {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let controller = PopupWindowController(resultHandler: resultHandler, pasteProbe: pasteProbe, toastController: toastController, settingsStore: settingsStore)
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: appPolicy
        )
        controller.show(for: context)
        return controller
    }

    /// Regression: a `.paste` result dismisses the popup, and `hide()` clears the live session
    /// context. The denyPaste policy must be captured BEFORE that hide — otherwise the Terminal
    /// escape hatch silently pastes instead of copying. The policy answers inside the unified
    /// decision (no probe consulted), so the "would happily paste" probe is overridden by the rule.
    @MainActor
    func testDeliverResultAppliesDenyPasteDespiteDismissingHide() async throws {
        let handler = RecordingHandler()
        // Probe would happily paste; the denyPaste policy alone must force a copy.
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: AppPolicyContext(denyPaste: true))
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
    }

    /// A nil delivery context (an explicit user request, e.g. the AI card's Paste button) must never
    /// be re-decided — even when the probe would say paste is unavailable.
    @MainActor
    func testNilDeliveryPassesPasteThroughUntouched() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.handleActionResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    // MARK: - Implicit .text delivery wiring (defaults preserved)

    /// Default settings (primary = paste): an implicit `.text` result delivers a paste and dismisses
    /// the popup — identical to today's string-return behavior.
    @MainActor
    func testTextDeliversPasteAndDismissesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
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
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertEqual(toast.currentFeedback?.message, "Copied")
    }

    /// User picks copy for the primary click: `.text` delivers a native copy (no toast) and dismisses.
    @MainActor
    func testTextDeliversCopyWhenPreferenceIsCopy() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "copy")
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast,
                                             settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.text("hello"))

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertNil(toast.currentFeedback, "a native copy fires no companion toast")
    }

    /// A secondary click with the default secondary = copy: `.text` copies without a toast.
    @MainActor
    func testTextSecondaryCopiesWithDefaultSettings() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        let stub = TextStubAction()
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("hello"))
        XCTAssertFalse(controller.isVisible)
    }

    // MARK: - Preview routing (implicit .text → AI result card)

    /// Preview preference on a primary click keeps the popup open and renders the returned text in
    /// the native AI result card (content mode) with the performing action's title — no effect is
    /// delivered to the handler.
    @MainActor
    func testTextPreviewKeepsPopupOpenAndShowsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while (controller.modeStore.mode != .content || !controller.isVisible) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(handler.results.isEmpty, "preview must not deliver any effect")
        XCTAssertTrue(controller.isVisible, "preview keeps the popup open")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.aiResult?.text, "hello")
        XCTAssertEqual(controller.modeStore.aiResult?.title, "My Action")
        XCTAssertFalse(controller.modeStore.aiResult?.isError ?? true)
    }

    /// Preview with cannot-paste hides the card's Paste button (modeStore.canPaste == false).
    @MainActor
    func testTextPreviewHidesPasteWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.canPaste != false && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.modeStore.canPaste, false, "preview card must gate Paste on the probe answer")
    }

    /// Preview with can-paste keeps Paste visible on the card.
    @MainActor
    func testTextPreviewKeepsPasteWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.canPaste == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotEqual(controller.modeStore.canPaste, false)
    }

    /// Esc collapses the preview card back to the actions bar (exitContent) without hiding the popup.
    @MainActor
    func testTextPreviewEscCollapsesToBar() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             settingsStore: store)
        defer { controller.hide() }
        controller.pendingActionTitle = "My Action"

        controller.deliverResult(.text("hello"))

        var deadline = Date().addingTimeInterval(3.0)
        while (controller.modeStore.mode != .content || !controller.isVisible) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        controller.exitContent()

        deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .actions && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertNil(controller.modeStore.aiResult)
        XCTAssertTrue(controller.isVisible, "collapsing the card never hides the popup")
    }

    /// A loading action with preview preference: the spinner hides and the popup re-shows as a
    /// content-mode card using the original selection.
    @MainActor
    func testLoadingTextPreviewReshowsPopupAsCard() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast,
                                             settingsStore: store)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(SlowTextStubAction(text: "loaded"), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(toast.isLoading, "the spinner must hide when the preview card re-shows")
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.aiResult?.text, "loaded")
        XCTAssertEqual(controller.modeStore.aiResult?.title, "Slow Text")
        XCTAssertTrue(controller.isVisible, "the popup must re-show as the preview card")
        XCTAssertTrue(handler.results.isEmpty)
    }

    /// A loading action with a paste preference keeps the existing settle path (deliver + spinner
    /// swap/hide) — no re-show.
    @MainActor
    func testLoadingTextPastePreferenceDeliversNormally() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.runLoadingAction(SlowTextStubAction(text: "loaded"), with: controllerCurrentContext(controller), isSecondaryClick: false)

        assertCase(try await awaitDelivery(from: handler), .paste("loaded"))
    }

    // MARK: - Preview routing review follow-ups (declared secondary + pending-state leak)

    /// A declared secondary beats the picker even when the raw result is `.text` with a preview
    /// preference: the popup must dismiss with the declared outcome (e.g. openURL), not stay open
    /// for a card that never renders. `shouldDismiss` verifies the actual resolved outcome.
    @MainActor
    func testTextPreviewWithDeclaredSecondaryDismisses() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.secondaryClickBehavior, value: "preview")
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             settingsStore: store)
        defer { controller.hide() }

        let url = URL(string: "https://alt")!
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .openURL(url)), performResult: .text("a"))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .openURL(url))
        XCTAssertFalse(controller.isVisible, "a dismissing declared secondary must dismiss even when the raw .text preference is preview")
    }

    /// The right-click perform path (runAction) snapshots the action's declared delivery into its
    /// own DeliveryContext and must not leave `pendingActionTitle`/`pendingDelivery` behind for a
    /// later completion-paste `deliverResult` — the preview card's title comes from the snapshotted
    /// context, and the completion paste must fire no stale declared toast.
    @MainActor
    func testRunActionPreviewDoesNotLeakDeclaredDeliveryOntoCompletionPaste() async throws {
        let handler = RecordingHandler()
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast,
                                             settingsStore: store)
        defer { controller.hide(); toast.hide() }

        let declared = StatusFeedback(message: "Saved", style: .info)
        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(primaryToast: declared), performResult: .text("a"))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: false)

        let deadline = Date().addingTimeInterval(3.0)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(controller.modeStore.aiResult?.title, "Declared", "the preview card must show the performing action's title")
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
        let controller = try shownController(resultHandler: handler,
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
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        controller.deliverResult(.paste("hello"))

        assertCase(try await awaitDelivery(from: handler), .paste("hello"))
    }

    // MARK: - Toast routing: paste→copy downgrade shows "Copied"; native copy shows nothing

    /// A `.paste` result downgraded to `.copy` (secondary click / cannot paste) surfaces the
    /// "Copied" toast. The toast is independent of the popup, so it works even though the popup hid.
    @MainActor
    func testDowngradeToCopyShowsCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(toast.currentFeedback?.message, "Copied")
        XCTAssertEqual(toast.currentFeedback?.style, .success)
    }

    /// When resultHandler.handle throws an error, the "Copied" success toast is NOT shown (an error status is shown instead).
    @MainActor
    func testDeliveryFailureDoesNotShowCopiedToast() async throws {
        let handler = FailingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.paste("hello"))

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotEqual(toast.currentFeedback?.message, "Copied")
        XCTAssertEqual(toast.currentFeedback?.style, .error)
    }

    /// A native `.copy` result is not a downgrade — it must show no toast.
    @MainActor
    func testNativeCopyShowsNoToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.deliverResult(.copy("hello"))

        _ = try await awaitDelivery(from: handler)
        XCTAssertNil(toast.currentFeedback, "native copy must not show the Copied toast")
    }

    /// Every `.toast` result routes to the toast (the single status surface). The popup is
    /// shown first (via `shownController`) so `panel` exists and the toast anchors to the popup's
    /// frame — matching production, where a nil panel would otherwise fall back to the cursor.
    @MainActor
    func testToastRoutesToToast() async throws {
        let toast = ToastPanelController()
        let controller = try shownController(resultHandler: RecordingHandler(),
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }
        controller.handleActionResult(.toast(StatusFeedback(message: "hello", style: .info)))
        XCTAssertEqual(toast.currentFeedback?.message, "hello")
        XCTAssertTrue(toast.isShowing)
        XCTAssertNotNil(toast.lastAnchorPoint, "status toast must anchor to the popup point, not the cursor")
    }

    // MARK: - Loading (slow-action) early-close flow

    /// A `showsLoading` action closes the popup immediately, shows a spinner toast, and fades the
    /// toast when the result lands with no description (`.success`).
    @MainActor
    func testLoadingActionShowsSpinnerThenFades() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
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
    private func controllerCurrentContext(_ controller: PopupWindowController) -> ActionContext {
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 300, y: 300),
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    /// A `showsLoading` action with an explicit `loadingMessage`; the controller must surface that
    /// message verbatim instead of the "Opening <title>…" default.
    @MainActor
    func testLoadingActionUsesCustomLoadingMessage() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
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

    /// When a loading action returns a toast declaring `keepVisible: true`, the settled toast must
    /// still auto-dismiss because the popup was already closed when loading started.
    @MainActor
    func testLoadingActionKeepVisibleToastAutoDismisses() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 30_000_000)
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        defer { controller.hide(); toast.hide() }

        controller.runLoadingAction(KeepVisibleToastLoadingAction(), with: controllerCurrentContext(controller), isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "spinner should be visible immediately")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(toast.currentFeedback?.message, "Formatted")
        XCTAssertFalse(toast.isLoading)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(toast.isShowing, "settled loading toast with keepVisible: true must auto-dismiss")
    }

    /// Hiding the popup controller must dismiss any keep-visible toast currently showing.
    @MainActor
    func testHideDismissesKeepVisibleToast() async throws {
        let toast = ToastPanelController()
        let controller = try shownController(resultHandler: RecordingHandler(),
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default,
                                             toastController: toast)
        controller.handleActionResult(.toast(StatusFeedback(message: "Pinned", style: .info, keepVisible: true)))
        XCTAssertTrue(toast.isShowing)
        controller.hide()
        XCTAssertFalse(toast.isShowing, "hide() must dismiss any keepVisible toast")
    }

    // MARK: - Secondary-click threading: runAction must propagate the click intent into the action context

    /// A right-click (secondary click) on an action must reach `perform` as
    /// `context.isSecondaryClick == true`, so Define returns `.copyDefinition` instead of opening
    /// Dictionary.
    @MainActor
    func testRunActionThreadsSecondaryClickIntoActionContext() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
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
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        let probe = SecondaryClickProbeAction()
        controller.runAction(probe, with: controllerCurrentContext(controller), isSecondaryClick: false)

        _ = try await awaitDelivery(from: handler)
        XCTAssertEqual(probe.lastPerformContext?.isSecondaryClick, false, "primary click must not set isSecondaryClick")
    }

    // MARK: - Declared delivery wiring: runAction must snapshot the action's delivery and render its toast

    /// An action declaring a distinct secondary outcome + secondary toast: a secondary (right-click)
    /// perform must deliver the declared secondary and surface the declared toast — the controller
    /// snapshots `action.delivery` and renders the resolved tuple's toast.
    @MainActor
    func testRunActionDeliversDeclaredSecondaryAndToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
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

    /// An action declaring a primary toast: a primary perform must surface it even when the result
    /// itself is a description-free `.success` (the toast is not tied to a paste→copy downgrade).
    @MainActor
    func testRunActionShowsDeclaredPrimaryToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = try shownController(resultHandler: handler,
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

    /// Completion buttons route `deliverResult(.paste(word))` straight in (PopupView `onResult`),
    /// bypassing `onWillPerformAction`. Model the left-click bar flow: the prior action's declared
    /// delivery is snapshotted into `pendingDelivery`, its dismissing `.toast` result
    /// routes through `deliverResult` (which consumes and clears the declaration), and the
    /// completion-word paste that follows must carry no declared secondary and fire no stale toast.
    @MainActor
    func testStaleDeclaredDeliveryDoesNotLeakOntoCompletionPaste() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = try shownController(resultHandler: handler,
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

    /// A top-level sequence carrying a script toast suppresses the delivery companion for its
    /// effects: even with a declared primary toast snapshotted onto the delivery, a `.copy` effect
    /// must not surface the declared toast — the script toast wins (one toast per run).
    @MainActor
    func testScriptToastWinsOverDeclaredToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = try shownController(resultHandler: handler,
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

    /// A top-level sequence carrying a script toast suppresses the delivery companion for its
    /// effects: the paste→copy downgrade's default "Copied" toast must not surface alongside the
    /// script toast (one toast per run).
    @MainActor
    func testScriptToastSuppressesDefaultCopiedToast() async throws {
        let handler = RecordingHandler()
        let toast = ToastPanelController(autoDismissNanoseconds: 60_000_000_000)
        let controller = try shownController(resultHandler: handler,
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

    // MARK: - Declared .paste secondary probes even on a secondary click

    /// A declared `.paste` secondary is pasted on a secondary click: the probe must still run (the
    /// force-copy short-circuit only applies when the click's outcome is a copy). With paste
    /// available the declared paste secondary is delivered as a paste, not downgraded to copy.
    @MainActor
    func testDeclaredPasteSecondaryPastesOnSecondaryClickWhenCanPaste() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: true),
                                             appPolicy: .default)
        defer { controller.hide() }

        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .paste("alt")))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .paste("alt"))
    }

    /// The same declared `.paste` secondary on a secondary click, but the target cannot paste: the
    /// probe runs (and answers no), downgrading the declared paste to a copy — never paste blindly.
    @MainActor
    func testDeclaredPasteSecondaryDowngradesToCopyWhenCannotPaste() async throws {
        let handler = RecordingHandler()
        let controller = try shownController(resultHandler: handler,
                                             pasteProbe: FixedProbe(result: false),
                                             appPolicy: .default)
        defer { controller.hide() }

        let stub = DeclaredDeliveryStub(delivery: ActionDelivery(secondary: .paste("alt")))
        controller.runAction(stub, with: controllerCurrentContext(controller), isSecondaryClick: true)

        assertCase(try await awaitDelivery(from: handler), .copy("alt"))
    }

    // MARK: - Builtin delivery declarations (uniform with extension actions)

    /// DefineAction keeps its `context.isSecondaryClick` code branch (`.copyDefinition`) and
    /// declares a secondary toast, so a secondary click surfaces "Copied definition" instead of a
    /// silent copy.
    func testDefineDeclaresSecondaryToast() {
        XCTAssertNotNil(DefineAction().delivery?.secondaryToast,
                        "DefineAction must declare a secondary toast for its code-branched .copyDefinition")
    }

    /// PasteAction relies on the default nil delivery: the resolver derives `.copy` for a secondary
    /// click and shows the default "Copied" toast. Builtins and extensions behave identically.
    func testPasteDeclaresNoDelivery() {
        XCTAssertNil(PasteAction().delivery,
                     "PasteAction must rely on the default nil delivery (paste→copy default)")
    }
}

/// Records every effect the handler is asked to deliver. @MainActor-isolated, matching the
/// `ActionResultHandler` protocol's main-actor methods.
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

/// A `showsLoading` action whose perform resolves after a short delay to a description-free
/// `.success` (e.g. Apple Music's empty-stdout AppleScript).
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

/// Records the `ActionContext` handed to `perform` so tests can assert the click intent
/// (isSecondaryClick) threaded through the controller's run path. Mutable state lives in a
/// synchronous lock-protected box so the Sendable `Action` conformance stays race-free.
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

/// An action carrying a declared `delivery` (secondary outcome + per-click toasts). Its default
/// perform returns a plain `.paste`, so a secondary click derives the declared secondary rather
/// than copying; `performResult` lets tests exercise non-paste results too.
private final class DeclaredDeliveryStub: Action, @unchecked Sendable {
    let id = "stub.declared"
    let title = "Declared"
    let icon: ActionIcon = .symbol("arrow.turn.down.right")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    var delivery: ActionDelivery? { declaredDelivery }
    private let declaredDelivery: ActionDelivery
    let performResult: ActionResult
    init(delivery: ActionDelivery, performResult: ActionResult = .paste("hello")) {
        self.declaredDelivery = delivery
        self.performResult = performResult
    }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { performResult }
}

/// An action whose perform returns implicitly returned text (a `.text` result), like the JS string
/// return / AppleScript output / shell stdout / text snippet runtimes.
private final class TextStubAction: Action, @unchecked Sendable {
    let id = "stub.text"
    let title = "Text Action"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    private let result: ActionResult
    init(result: ActionResult = .text("hello")) { self.result = result }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult { result }
}

/// A `showsLoading` action returning `.text` after a short delay (loading + preview re-show path).
private final class SlowTextStubAction: Action, @unchecked Sendable {
    let id = "stub.slowtext"
    let title = "Slow Text"
    let icon: ActionIcon = .symbol("text.alignleft")
    var chrome: ActionChrome { ActionChrome(source: .builtin, showsLoading: true) }
    private let text: String
    init(text: String = "loaded") { self.text = text }
    func isEnabled(for context: ActionContext) -> Bool { true }
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    func perform(_ context: ActionContext) async throws -> ActionResult {
        try await Task.sleep(nanoseconds: 30_000_000)
        return .text(text)
    }
}

/// Lock-protected capture box for the context an action performed with (synchronous accessors, so
/// it stays callable from an async `perform`).
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
