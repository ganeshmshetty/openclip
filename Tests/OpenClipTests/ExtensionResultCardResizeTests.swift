import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// Extension results — a shell/JS/AppleScript action returning text, delivered inline while the
/// popup is up or through the loading re-show after a spinner — render in the same result card as
/// AI answers, so they get the same handles and the same remembered maximum. These drive both
/// delivery paths end to end with an extension-package action and pin that.
@MainActor
final class ExtensionResultCardResizeTests: XCTestCase {

    private let ring = 2 * PopupMetrics.popupShadowInset
    private let remembered = CGSize(width: 520, height: 440)
    private let longText = (1...60)
        .map { "Line \($0): a grammar suggestion from an extension that keeps going for quite a while." }
        .joined(separator: "\n")

    private struct FixedProbe: PasteAvailabilityProbing {
        let result: Bool?
        func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? { result }
    }

    /// An extension-package action returning text: inline when `showsLoading` is false, through
    /// the spinner + re-show path when true.
    private final class ExtensionTextAction: Action, @unchecked Sendable {
        let id = "com.test.pkg.grammar"
        let title = "Grammar Check"
        let icon: ActionIcon = .symbol("text.badge.checkmark")
        private let text: String
        private let loading: Bool
        init(text: String, loading: Bool) {
            self.text = text
            self.loading = loading
        }
        var chrome: ActionChrome { ActionChrome(source: .extensionPkg(packageID: "com.test.pkg"), showsLoading: loading) }
        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult {
            if loading { try await Task.sleep(nanoseconds: 30_000_000) }
            return .text(text)
        }
    }

    private func makeSelection(on screen: NSScreen) -> SelectionContext {
        SelectionContext(
            text: "hey how are you doing",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        )
    }

    /// A shown popup with the "preview" preference (text results render in the card) and a
    /// remembered card maximum.
    private func shownController(on screen: NSScreen) -> (PopupWindowController, MemorySettingsStore, ToastPanelController) {
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        store.set(SettingKey.resultCardWidth, value: Double(remembered.width))
        store.set(SettingKey.resultCardHeight, value: Double(remembered.height))
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: FixedProbe(result: true),
            toastController: toast,
            settingsStore: store
        )
        controller.show(for: makeSelection(on: screen))
        return (controller, store, toast)
    }

    /// Waits for content mode, then for the fit-to-content retries to land.
    private func waitForCard(_ controller: PopupWindowController, timeout: TimeInterval = 3.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.modeStore.mode != .content && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    /// Inline path: the popup is up, an extension action returns text, and the card replaces the
    /// bar — at the remembered maximum, with the extension's own title and icon.
    func testInlineExtensionResultOpensAtTheRememberedMaximum() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let (controller, store, toast) = shownController(on: screen)
        defer { controller.hide(); toast.hide() }
        let panel = try XCTUnwrap(controller.panel)
        let action = ExtensionTextAction(text: longText, loading: false)

        controller.pendingActionTitle = action.title
        controller.pendingActionIcon = action.icon
        controller.deliverResult(.text(longText))
        await waitForCard(controller)

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Grammar Check")
        XCTAssertEqual(controller.modeStore.resultCard?.icon, action.icon, "the extension's own icon reaches the card")
        XCTAssertEqual(controller.modeStore.resultCardSize, remembered, "the remembered maximum applies to an extension's card")
        XCTAssertEqual(panel.frame.width, remembered.width + ring, accuracy: 1.0, "long lines fill the remembered width")
        XCTAssertEqual(panel.frame.height, remembered.height + ring, accuracy: 1.0, "sixty lines stop at the remembered height")
        XCTAssertGreaterThan(panel.heightCap, PopupMetrics.popupMaxHeight, "the shared cap is lifted for it")

        // The handles work on it like on any card, and the size is remembered under the same keys.
        let grip = CGPoint(x: panel.frame.maxX, y: panel.frame.minY)
        let target = CGPoint(x: grip.x - 100, y: grip.y + 100)
        controller.handleResize(.bottomRight, phase: .began, mouseLocation: grip)
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: target)
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: target)
        XCTAssertEqual(store.get(SettingKey.resultCardWidth), remembered.width - 100, accuracy: 1.0)
        XCTAssertEqual(store.get(SettingKey.resultCardHeight), remembered.height - 100, accuracy: 1.0)
    }

    /// A short extension result keeps a small card even with a large remembered maximum.
    func testShortInlineExtensionResultStaysSmall() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let (controller, _, toast) = shownController(on: screen)
        defer { controller.hide(); toast.hide() }
        let panel = try XCTUnwrap(controller.panel)

        controller.pendingActionTitle = "Grammar Check"
        controller.deliverResult(.text("Looks good."))
        await waitForCard(controller)

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCardSize, remembered)
        XCTAssertEqual(panel.frame.width, PopupMetrics.aiCardMinWidth + ring, accuracy: 1.0, "the maximum is not a minimum")
        XCTAssertEqual(panel.frame.height, PopupMetrics.aiCardMinHeight + ring, accuracy: 1.0)
    }

    /// Loading path: a `showsLoading` extension early-closes the popup for a spinner, then the
    /// popup re-shows straight into the card — which must open at the remembered maximum too.
    func testLoadingExtensionResultReopensAtTheRememberedMaximum() async throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let (controller, store, toast) = shownController(on: screen)
        defer { controller.hide(); toast.hide() }
        let action = ExtensionTextAction(text: longText, loading: true)
        let context = ActionContext(selection: makeSelection(on: screen), modifiers: [])

        controller.runLoadingAction(action, with: context, isSecondaryClick: false)
        XCTAssertTrue(toast.isLoading, "the spinner shows while the extension runs")
        await waitForCard(controller)

        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertFalse(toast.isLoading, "the spinner hides when the card re-shows")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Grammar Check")
        XCTAssertEqual(controller.modeStore.resultCard?.icon, action.icon)
        XCTAssertEqual(controller.modeStore.resultCardSize, remembered, "the re-shown card restores the remembered maximum")
        XCTAssertEqual(panel.frame.width, remembered.width + ring, accuracy: 1.0)
        XCTAssertEqual(panel.frame.height, remembered.height + ring, accuracy: 1.0)
        XCTAssertTrue(screen.visibleFrame.insetBy(dx: -1, dy: -1).contains(panel.frame), "the re-shown card stays on screen: \(panel.frame)")

        controller.handleResize(.right, phase: .began, mouseLocation: CGPoint(x: 800, y: 500))
        controller.handleResize(.right, phase: .changed, mouseLocation: CGPoint(x: 760, y: 500))
        controller.handleResize(.right, phase: .ended, mouseLocation: CGPoint(x: 760, y: 500))
        XCTAssertEqual(store.get(SettingKey.resultCardWidth), remembered.width - 40, accuracy: 1.0)
        XCTAssertEqual(store.get(SettingKey.resultCardHeight), remembered.height, accuracy: 1.0, "the right edge leaves the height alone")
    }
}
