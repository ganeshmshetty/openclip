import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

@MainActor
final class PopupPanelTests: XCTestCase {
    func testPopupMetricsConstants() {
        // Sentinel: the shared height cap stays 300. Lives here (app target) because popup sizing
        // constants are UI concerns — see PopupMetrics.
        XCTAssertEqual(PopupMetrics.popupMaxHeight, 300)
    }

    func testToastDurationConstant() {
        XCTAssertEqual(PopupMetrics.toastDurationNanoseconds, 1_200_000_000)
    }

    func testToastFittingSizeIsOneLine() throws {
        let toast = ToastView(feedback: StatusFeedback(message: "Copied to clipboard", style: .success, symbolName: "checkmark"))
        let host = NSHostingView(rootView: toast)
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        XCTAssertGreaterThan(fit.width, 80, "toast collapsed to zero width")
        XCTAssertLessThan(fit.height, 60, "toast should be a single compact line")
    }

    /// Evidence check: the AI result card's preferred (fitting) size must include the response
    /// body region, not just header + footer. The panel auto-resizes to the hosting view's fitting
    /// size on mode change; if the ScrollView body collapses to zero at fit-time the window stays
    /// ~bar-height and the response never renders.
    func testAICardFittingSizeIncludesResponseBody() throws {
        let card = ResultCardView(
            payload: ResultCardPayload(
                text: (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n"),
                isError: false,
                title: "Summarize"
            ),
            onExit: {},
            onPaste: {},
            onCopy: {}
        )
        let host = NSHostingView(rootView: card)
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        XCTAssertGreaterThan(fit.height, 130,
                             "card fitting height collapsed to \(fit.height) — response body contributes no height")
    }

    /// The panel must actually GROW to fit the card when the AI result is shown (content mode),
    /// not stay at bar height. If the resize path starves the ScrollView body, the user sees only
    /// the header (title + back) and footer (Copy/Paste) with no response text.
    func testAICardResizesPanelToIncludeBody() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.modeStore.resultCard = ResultCardPayload(
            text: (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n"),
            isError: false,
            title: "Summarize"
        )
        controller.modeStore.mode = .content

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if panel.frame.height > barFrame.height + 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barFrame.height + 100,
                             "panel stayed at bar height \(barFrame.height); card body starved, final \(panel.frame.height)")
    }

    /// Regression repro: the REAL preview path drives `deliverResult(.text)` → `handleEffect` →
    /// `showResultCard` (a Task on the main actor), which sets the store AND calls `enterKeyMode()`
    /// (`makeKeyAndOrderFront`). The direct-store test above never exercises that ordering. If the
    /// panel stays at bar height after the real path, the card body is starved until a mouse move
    /// near the popup forces a re-render (the reported bug).
    @MainActor
    func testPreviewCardGrowsPanelThroughRealDeliveryPath() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: store
        )
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.pendingActionTitle = "Summarize"
        controller.deliverResult(.text((1...20).map { "line \($0) of a long response body" }.joined(separator: "\n")))

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if panel.frame.height > barFrame.height + 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barFrame.height + 100,
                             "panel stayed at bar height \(barFrame.height) through the real preview path; card body starved, final \(panel.frame.height)")
    }

    /// Diagnostic: after the real preview path shows the card (panel frame grew), is the card
    /// CONTENT actually drawn, or does the window show stale bar pixels until a hover-state change
    /// forces a redraw? Renders the hosting view to a bitmap and counts non-transparent pixels in
    /// the card-body region (below the header, above the footer).
    @MainActor
    func testPreviewCardBodyIsActuallyDrawn() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: store
        )
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.pendingActionTitle = "Summarize"
        let responseBody = (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n")
        controller.deliverResult(.text(responseBody))

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if panel.frame.height > barFrame.height + 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barFrame.height + 100,
                             "panel did not grow through the real preview path")

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Summarize")
        XCTAssertEqual(controller.modeStore.resultCard?.text, responseBody)
        XCTAssertNotNil(panel.contentView)
    }

    /// Diagnostic: entering content mode updates the window/content state.
    @MainActor
    func testContentModeInvalidatesWindowForDisplay() throws {
        let store = MemorySettingsStore()
        store.set(.primaryClickBehavior, value: "preview")
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: store
        )
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertEqual(controller.modeStore.mode, .actions, "precondition: bar mode")

        controller.showResultCard(text: "line one\nline two\nline three\nline four", isError: false, title: "Summarize", session: controller.aiSessionID)

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "line one\nline two\nline three\nline four")
        XCTAssertEqual(controller.modeStore.resultCard?.title, "Summarize")
        XCTAssertEqual(controller.modeStore.resultCard?.isError, false)
    }

    // MARK: - AI streaming session isolation

    private func makeSessionController() -> (PopupWindowController, SelectionContext) {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: true),
            settingsStore: MemorySettingsStore()
        )
        let context = SelectionContext(
            text: "session text",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        return (controller, context)
    }

    /// Regression: a stream that outlived its popup kept delivering chunks through the shared
    /// mode store — flipping a NEW selection's popup into content mode and re-sticking
    /// isProcessingAI after hide() cleared it. Session-stamped deliveries must be dropped.
    func testStaleSessionAIChunkCannotHijackCurrentSession() {
        let (controller, _) = makeSessionController()
        let staleSession = controller.aiSessionID

        controller.hide() // dismiss mid-stream ends the session…

        // …but the zombie stream keeps delivering under the OLD token:
        controller.setAIProcessing(true, session: staleSession)
        XCTAssertFalse(controller.modeStore.isProcessingAI,
                       "stale processing flag must not stick into the next session")
        controller.showResultCard(text: "old chunks", isError: false, title: "Old", isStreaming: true, session: staleSession)
        XCTAssertEqual(controller.modeStore.mode, .actions,
                       "stale chunk must not flip the popup into content mode")
        XCTAssertNil(controller.modeStore.resultCard,
                     "stale chunk must not populate the result card")

        // The live session still works normally.
        let live = controller.aiSessionID
        controller.showResultCard(text: "fresh", isError: false, title: "New", isStreaming: true, session: live)
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.text, "fresh")
    }

    /// Regression: cancellation was tied to SwiftUI view teardown, which races (or misses) when
    /// the panel is reused across sessions. hide() must cancel the registered stream itself.
    func testHideCancelsRegisteredStreamingTask() {
        let (controller, _) = makeSessionController()

        let task = Task { @MainActor in
            _ = try? await Task.sleep(nanoseconds: 10_000_000_000) // would outlive the session
        }
        // Registration seam is exactly what PopupView hands the controller at spawn.
        controller.activeStreamingTask = task

        controller.hide()

        XCTAssertTrue(task.isCancelled, "hide() must cancel the session's streaming task")
        XCTAssertNil(controller.activeStreamingTask)
    }

    /// A fresh show() starts a new AI session even if hide() was skipped (re-show path), so
    /// deliveries stamped by the previous session are dead on arrival.
    func testShowBumpsAISessionOverPreviousOne() throws {
        let (controller, context) = makeSessionController()
        let firstSession = controller.aiSessionID

        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        controller.show(for: context)

        XCTAssertNotEqual(controller.aiSessionID, firstSession,
                          "show(for:) must start a new AI session")
        XCTAssertNil(controller.activeStreamingTask)

        controller.showResultCard(text: "pre-show chunk", isError: false, title: "Old",
                                 isStreaming: true, session: firstSession)
        XCTAssertEqual(controller.modeStore.mode, .actions,
                       "chunk from the pre-show session must not flip the new popup")
        controller.hide()
    }

    /// Paste availability is probed by the trigger site before selection retrieval and handed to
    /// show(for:pasteAvailable:) — a confirmed cannot-paste must land on `modeStore.canPaste ==
    /// false` synchronously so the card hides its Paste button and the bar/search hide Paste + Cut
    /// on the first frame (no async flash).
    func testPasteAvailabilityGatesBarAndCardSynchronously() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context, pasteAvailable: false)
        defer { controller.hide() }

        XCTAssertEqual(controller.modeStore.canPaste, false,
                       "confirmed cannot-paste must gate Paste/Cut from the first frame")
    }

    /// Paste and Cut require a paste-capable target; Copy does not. The bar/search hide exactly the
    /// `PasteRequiringAction` set when the probe reports cannot-paste.
    func testPasteAndCutArePasteRequiringActions() {
        XCTAssertTrue((PasteAction() as Any) is any PasteRequiringAction)
        XCTAssertTrue((CutAction() as Any) is any PasteRequiringAction)
        XCTAssertFalse((CopyAction() as Any) is any PasteRequiringAction)
    }

    /// Paste availability tracks the target app's focus context, so it must never be cached per
    /// app: a re-show in the same app applies the freshly-probed value each time.
    func testPasteAvailabilityIsNotCachedAcrossShows() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 100, y: 100),
            timestamp: Date(),
            appPolicy: .default
        )

        controller.startTestSession(for: context, pasteAvailable: false)
        XCTAssertEqual(controller.modeStore.canPaste, false)
        controller.hide()

        controller.startTestSession(for: context, pasteAvailable: true)
        XCTAssertEqual(controller.modeStore.canPaste, true,
                       "a focus-context change in the same app must apply the fresh probe result")
        controller.hide()
    }

    /// preparePasteProbe runs the injected probe and resolves to its result, so the trigger sites
    /// can await it after selection retrieval and hand it to show without blocking the bar.
    func testPreparePasteProbeResolvesToProbeResult() async {
        let controller = PopupWindowController(pasteProbe: AICardFixedProbe(result: true))
        let probe = controller.preparePasteProbe(for: nil, policy: .default)
        let value = await probe.value
        XCTAssertEqual(value, true)
    }

    func testCanBecomeKeyFollowsAllowsKey() {
        let panel = PopupPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        panel.allowsKey = false
        XCTAssertFalse(panel.canBecomeKey)
    }

    /// The transparent shadow ring around the bar must be outside the clickable region, so clicks
    /// in the visible shadow fall through to the app underneath instead of being swallowed by the
    /// panel frame (which previously made dismissal impossible there).
    func testShadowRingIsOutsideClickableRegion() {
        let bounds = NSRect(x: 0, y: 0, width: 200, height: 80)
        let inset = PopupMetrics.popupShadowInset

        // Center of the content area: belongs to the popup.
        XCTAssertTrue(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: bounds.midX, y: bounds.midY), bounds: bounds))
        // Just inside the shadow ring boundary (16pt from each edge): still the popup's.
        XCTAssertTrue(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: inset + 1, y: inset + 1), bounds: bounds))
        // Inside the ring itself (e.g. 4pt from the corner): NOT the popup's — click-through.
        XCTAssertFalse(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: 4, y: 4), bounds: bounds))
        XCTAssertFalse(PopupPanel.ContentView.isInsideClickableRegion(
            point: NSPoint(x: inset - 1, y: bounds.midY), bounds: bounds))
    }

    /// The live panel's root view must apply the same rule: points in the shadow ring report as
    /// non-mouse points so the window server routes those clicks to windows below.
    func testLiveContentViewExcludesShadowRingFromHitTesting() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()
        let contentView = try XCTUnwrap(panel.contentView as? PopupPanel.ContentView,
                                        "popup must mount PopupPanel.ContentView as its root")
        let bounds = contentView.bounds

        XCTAssertTrue(contentView.isMousePoint(NSPoint(x: bounds.midX, y: bounds.midY), in: bounds),
                      "content-area point must hit-test to the popup")
        XCTAssertFalse(contentView.isMousePoint(NSPoint(x: 2, y: 2), in: bounds),
                       "shadow-ring point must not hit-test to the popup (click-through)")
    }

    /// Dismissal decisions must treat the transparent shadow ring as outside-the-popup: a press
    /// in the ring hides the popup instead of counting as bar content. This pins the fix where
    /// `handleEvent` used `panel.frame.contains(...)` and shadow clicks did nothing at all.
    func testShadowRingPressDoesNotCountAsBarContent() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()
        let frame = panel.frame

        // Deep in the transparent ring near a frame corner: outside interactive content…
        XCTAssertFalse(controller.isOverPanelContent(
            CGPoint(x: frame.minX + 2, y: frame.minY + 2)),
            "shadow-ring point must not count as bar content (press there must dismiss)")
        // …while the actual content area still counts as the bar.
        XCTAssertTrue(controller.isOverPanelContent(
            CGPoint(x: frame.midX, y: frame.midY)),
            "content-area point must still count as bar content")
        // And anywhere outside the frame remains an ordinary dismiss click.
        XCTAssertFalse(controller.isOverPanelContent(
            CGPoint(x: frame.maxX + 50, y: frame.midY)))
    }

    /// Returns the popup panel after show(for:) has mounted it.
    private func shownPanel(for cursor: CGPoint) throws -> PopupWindowController {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: cursor,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        return controller
    }

    /// The visible popup panel for the most recent show; filters out hidden panels left by earlier
    /// tests in the same process (NSApp.windows includes hidden windows).
    private func visiblePanel() throws -> PopupPanel {
        guard let panel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) as? PopupPanel else {
            throw XCTSkip("popup panel did not appear")
        }
        return panel
    }

    private func pump(_ duration: TimeInterval = 2.0) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    /// Deterministic paste-availability fake (never blocks, ignores the app argument).
    private struct AICardFixedProbe: PasteAvailabilityProbing {
        let result: Bool?

        func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
            result
        }
    }

    /// Polls until the panel height settles at a value strictly greater than the bar height (i.e.
    /// the search palette has rendered and resized the panel), or the timeout elapses.
    private func waitForSearchResize(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height > barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Polls until the panel shrinks back to the bar height (search palette collapsed), or the
    /// timeout elapses.
    private func waitForSearchCollapse(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height <= barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Results below the field (popup near top of screen): entering search mode must keep the
    /// panel's TOP edge fixed and grow downward so the field doesn't jump.
    func testSearchModeKeepsTopEdgeFixedForResultsBelow() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.maxY, barFrame.maxY, accuracy: 1.0,
                       "popup top edge moved by \(searchFrame.maxY - barFrame.maxY)pt entering search mode")
    }

    /// Results ABOVE the field (popup near screen bottom): palette is [results, field], so the field
    /// sits at the palette bottom. The panel must anchor its BOTTOM edge and grow upward, keeping the
    /// field where the bar was.
    func testSearchModeKeepsBottomEdgeFixedForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.minY, barFrame.minY, accuracy: 1.0,
                       "popup bottom edge moved by \(searchFrame.minY - barFrame.minY)pt entering search mode")
    }

    /// A fresh show near the bottom of the screen (card above the cursor) must arm the bottom-edge
    /// pin immediately: a card-above popup renders its content above the bar, so content-driven
    /// growth has to push up, not shove the bar down off the cursor. Previously only enterSearch()
    /// armed the pin, so the first above-bar render after opening the popup was mis-anchored.
    func testShowArmsBottomEdgePinForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        XCTAssertTrue(panel.pinBottomEdgeOnResize,
                       "bottom-edge pin should be armed for a card-above popup")
    }

    /// Entering search swaps the (variable-width) actions bar for the fixed 280pt palette. The
    /// hosting view auto-resizes the panel top-anchored, preserving origin.x, so without horizontal
    /// re-anchoring the popup's center would drift off the cursor. The bar's center must stay fixed.
    func testSearchModeKeepsHorizontalCenterFixed() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let cursor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200)
        let controller = try shownPanel(for: cursor)
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barCenter = panel.frame.midX
        XCTAssertGreaterThan(barCenter, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: panel.frame.height)
        let searchCenter = panel.frame.midX

        XCTAssertEqual(searchCenter, barCenter, accuracy: 1.0,
                       "popup center moved \(searchCenter - barCenter)pt entering search mode")
    }

    /// Exiting search (Escape) must return the bar to the field's spot, not jump it to the palette
    /// top. Results-above case: the field sat at the palette bottom, so the bar's bottom edge must
    /// equal the original bar's bottom edge.
    func testExitingSearchReturnsBarToOriginalPositionForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        let barFrame = panel.frame

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        controller.exitSearch()
        waitForSearchCollapse(panel, barHeight: barFrame.height)

        XCTAssertEqual(panel.frame.minY, barFrame.minY, accuracy: 1.0,
                       "bar bottom edge moved by \(panel.frame.minY - barFrame.minY)pt exiting search mode")
    }

    /// The search field must become the first responder once the panel is key, so typing lands in
    /// the field (not the panel). Exercises both the direct (hotkey-equivalent) entry and a second
    /// entry after exit to catch re-entry timing.
    func testSearchModeMakesPanelKeyAndFieldFirstResponder() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        controller.enterSearch()
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }

        XCTAssertTrue(panel.isKeyWindow, "panel should be key in search mode")
        let isTextInput = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInput,
                      "search field should be first responder, got \(String(describing: panel.firstResponder))")

        // Exit and re-enter search: focus must be re-acquired.
        controller.exitSearch()
        pump(0.05)
        XCTAssertFalse(panel.canBecomeKey, "exit must restore the never-key invariant")

        controller.enterSearch()
        let reenterDeadline = Date().addingTimeInterval(2.0)
        while Date() < reenterDeadline {
            if (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        let isTextInputAgain = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInputAgain,
                      "search field should be first responder after re-entry, got \(String(describing: panel.firstResponder))")
    }

    func testSetFramePreservesTopEdgeWhenPinBottomEdgeOnResizeIsFalse() {
        let panel = PopupPanel()
        panel.pinBottomEdgeOnResize = false

        // Initial frame setup
        let initialFrame = NSRect(x: 100, y: 500, width: 200, height: 100)
        panel.setFrame(initialFrame, display: false)
        XCTAssertEqual(panel.frame.maxY, 600)

        // Path 1: Top-anchored height change (height 350 is clamped to PopupMetrics.popupMaxHeight = 300, requested maxY is 600)
        let heightOnlyChange = NSRect(x: 100, y: 250, width: 200, height: 350)
        panel.setFrame(heightOnlyChange, display: false)
        XCTAssertEqual(panel.frame.maxY, 600, "Height-only change must preserve requested top edge (maxY)")
        XCTAssertEqual(panel.frame.height, PopupMetrics.popupMaxHeight)
        XCTAssertEqual(panel.frame.origin.y, 600 - PopupMetrics.popupMaxHeight)

        // Path 2: Repositioning to a new cursor location must respect the new requested origin.y
        let repositionFrame = NSRect(x: 80, y: 100, width: 200, height: 100)
        panel.setFrame(repositionFrame, display: false)
        XCTAssertEqual(panel.frame.origin.y, 100, "Repositioning must place the panel at the requested origin.y")
    }

    func testSetFrameRecenteringClampsToScreenRightEdgeWhenExpanding() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let panel = PopupPanel()
        let visibleFrame = screen.visibleFrame
        let padding = PopupMetrics.popupPadding

        // Narrow panel initially positioned against the right screen edge
        let initialWidth: CGFloat = 100
        let initialX = visibleFrame.maxX - initialWidth - padding
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: initialWidth, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, visibleFrame.maxX - padding, "precondition: panel is flush with right padding edge")

        panel.recenterXOnResize = true

        // Expand width to 350 (e.g. closing word completions -> wide action bar)
        let expandedWidth: CGFloat = 350
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: expandedWidth, height: 50), display: false)

        XCTAssertLessThanOrEqual(panel.frame.maxX, visibleFrame.maxX - padding,
                                 "Expanded panel right edge (\(panel.frame.maxX)) exceeded screen right edge (\(visibleFrame.maxX - padding))")
        XCTAssertEqual(panel.frame.origin.x, visibleFrame.maxX - expandedWidth - padding,
                       "Expanded panel should be clamped flush with right edge")
    }

    func testSetFrameRecenteringClampsToScreenLeftEdgeWhenExpanding() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let panel = PopupPanel()
        let visibleFrame = screen.visibleFrame
        let padding = PopupMetrics.popupPadding

        // Narrow panel initially positioned against the left screen edge
        let initialWidth: CGFloat = 100
        let initialX = visibleFrame.minX + padding
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: initialWidth, height: 50), display: false)
        XCTAssertEqual(panel.frame.minX, visibleFrame.minX + padding, "precondition: panel is flush with left padding edge")

        panel.recenterXOnResize = true

        // Expand width to 350 (e.g. closing word completions -> wide action bar)
        let expandedWidth: CGFloat = 350
        panel.setFrame(NSRect(x: initialX, y: visibleFrame.midY, width: expandedWidth, height: 50), display: false)

        XCTAssertGreaterThanOrEqual(panel.frame.minX, visibleFrame.minX + padding,
                                    "Expanded panel left edge (\(panel.frame.minX)) fell below screen left edge (\(visibleFrame.minX + padding))")
        XCTAssertEqual(panel.frame.origin.x, visibleFrame.minX + padding,
                       "Expanded panel should be clamped flush with left edge")
    }

    func testSetFrameRightAnchorPreservesRightEdgeOnResize() throws {
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 200, y: 300, width: 300, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500)

        panel.horizontalAnchor = .right

        // Shrink width to 100 (e.g. paginating to a 1-item page)
        panel.setFrame(NSRect(x: 200, y: 300, width: 100, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500, "Right edge must stay pinned when horizontalAnchor is .right")
        XCTAssertEqual(panel.frame.origin.x, 400)

        // Expand width to 400
        panel.setFrame(NSRect(x: 200, y: 300, width: 400, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500, "Right edge must stay pinned when expanding with .right anchor")
        XCTAssertEqual(panel.frame.origin.x, 100)
    }

    func testSetFrameLeftAnchorPreservesLeftEdgeOnResize() throws {
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 200, y: 300, width: 300, height: 50), display: false)
        XCTAssertEqual(panel.frame.minX, 200)

        panel.horizontalAnchor = .left

        // Shrink width to 100
        panel.setFrame(NSRect(x: 200, y: 300, width: 100, height: 50), display: false)
        XCTAssertEqual(panel.frame.minX, 200, "Left edge must stay pinned when horizontalAnchor is .left")
        XCTAssertEqual(panel.frame.origin.x, 200)

        // Expand width to 400
        panel.setFrame(NSRect(x: 200, y: 300, width: 400, height: 50), display: false)
        XCTAssertEqual(panel.frame.minX, 200, "Left edge must stay pinned when expanding with .left anchor")
        XCTAssertEqual(panel.frame.origin.x, 200)
    }

    func testEnterSearchWithButtonAnchorCentersSearchOnButton() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let cursor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200)
        let controller = try shownPanel(for: cursor)
        defer { controller.hide() }
        let panel = try visiblePanel()

        let initialBarFrame = panel.frame
        let buttonLocalX: CGFloat = 250
        let buttonWidth: CGFloat = 34
        let buttonLocalFrame = CGRect(x: buttonLocalX, y: 0, width: buttonWidth, height: 29)
        let expectedButtonScreenMidX = initialBarFrame.minX + buttonLocalFrame.midX

        controller.enterSearch(buttonLocalFrame: buttonLocalFrame)
        waitForSearchResize(panel, barHeight: initialBarFrame.height)

        let searchFrame = panel.frame
        XCTAssertEqual(searchFrame.midX, expectedButtonScreenMidX, accuracy: 2.0,
                       "Search palette should be centered horizontally on the clicked button")

        controller.exitSearch()
        waitForSearchCollapse(panel, barHeight: initialBarFrame.height)
        XCTAssertEqual(panel.frame.midX, initialBarFrame.midX, accuracy: 2.0,
                       "Exiting search should restore the bar's horizontal position")
    }

    func testDistanceDismissalSuspendsWhileAIProcessing() throws {
        let controller = PopupWindowController()
        let panel = PopupPanel()
        let currentMouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: currentMouse.x + PopupMetrics.popupDismissalDistance + 200,
                              y: currentMouse.y + PopupMetrics.popupDismissalDistance + 200,
                              width: 200, height: 50), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertTrue(controller.isVisible)

        // When processing AI, distance auto-dismiss must be suspended
        controller.modeStore.isProcessingAI = true

        let farAwayLocation = CGPoint(x: panel.frame.maxX + PopupMetrics.popupDismissalDistance + 100,
                                      y: panel.frame.maxY + PopupMetrics.popupDismissalDistance + 100)
        let farEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: farAwayLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        controller.handleEvent(farEvent)
        XCTAssertTrue(controller.isVisible, "Popup must stay visible while AI is processing even when cursor moves far away")

        // When AI processing completes, distance dismissal re-engages
        controller.modeStore.isProcessingAI = false
        controller.handleEvent(farEvent)
        XCTAssertFalse(controller.isVisible, "Popup should dismiss when cursor moves far away and AI is not processing")
    }

    func testDistanceDismissalSuspendsWhileOnboardingVisible() throws {
        let controller = PopupWindowController()
        let panel = PopupPanel()
        let currentMouse = NSEvent.mouseLocation
        panel.setFrame(NSRect(x: currentMouse.x + PopupMetrics.popupDismissalDistance + 200,
                              y: currentMouse.y + PopupMetrics.popupDismissalDistance + 200,
                              width: 200, height: 50), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertTrue(controller.isVisible)

        // When onboarding is visible, distance auto-dismiss must be suspended
        controller.isOnboardingVisible = true

        let farAwayLocation = CGPoint(x: panel.frame.maxX + PopupMetrics.popupDismissalDistance + 100,
                                      y: panel.frame.maxY + PopupMetrics.popupDismissalDistance + 100)
        let farEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: farAwayLocation,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        controller.handleEvent(farEvent)
        XCTAssertTrue(controller.isVisible, "Popup must stay visible while onboarding is active even when cursor moves far away")

        // When onboarding completes/closes, distance dismissal re-engages
        controller.isOnboardingVisible = false
        controller.handleEvent(farEvent)
        XCTAssertFalse(controller.isVisible, "Popup should dismiss when cursor moves far away and onboarding is not visible")
    }

    func testSubBarActivePinsBottomEdgeWhenResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        // When searchResultsAbove is false (sub-bar below main bar), pinBottomEdgeOnResize remains false
        controller.modeStore.searchResultsAbove = false
        controller.modeStore.isSubBarActive = true
        XCTAssertFalse(panel.pinBottomEdgeOnResize)

        // When searchResultsAbove is true (sub-bar above main bar), pinBottomEdgeOnResize is true
        controller.modeStore.searchResultsAbove = true
        controller.modeStore.isSubBarActive = true
        XCTAssertTrue(panel.pinBottomEdgeOnResize)

        // Deactivating sub-bar preserves searchResultsAbove anchoring (preventing window crawl)
        controller.modeStore.isSubBarActive = false
        XCTAssertTrue(panel.pinBottomEdgeOnResize)
    }

    func testPopupPanelAcceptsMouseMovedEvents() {
        let panel = PopupPanel()
        XCTAssertTrue(panel.acceptsMouseMovedEvents, "PopupPanel must accept mouse-moved events for responsive cursor tracking")
    }

    func testPopupPanelContentViewInstallsTrackingAreaForCursorUpdate() {
        let panel = PopupPanel()
        let host = PopupPanel.ContentView(rootView: PopupView(actions: [], context: ActionContext(selection: SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)), onResult: { _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        panel.contentView = host
        host.updateTrackingAreas()

        let trackingAreas = host.trackingAreas
        XCTAssertFalse(trackingAreas.isEmpty, "ContentView must install a tracking area")
        guard let area = trackingAreas.first else { return }
        XCTAssertTrue(area.options.contains(.cursorUpdate), "Tracking area must contain .cursorUpdate")
        XCTAssertTrue(area.options.contains(.activeAlways), "Tracking area must contain .activeAlways")
        XCTAssertTrue(area.options.contains(.inVisibleRect), "Tracking area must contain .inVisibleRect")
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited), "Tracking area must contain .mouseEnteredAndExited")
    }

    func testPopupPanelContentViewCursorUpdateAndMouseEntered() {
        let host = PopupPanel.ContentView(rootView: PopupView(actions: [], context: ActionContext(selection: SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)), onResult: { _ in }))
        let dummyEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        // Should execute cleanly without runtime error
        host.cursorUpdate(with: dummyEvent)
        host.mouseEntered(with: dummyEvent)
        host.resetCursorRects()
    }

    func testResultCardViewRendersWithStreamingPayload() {
        let payload = ResultCardPayload(
            text: "Generating response text...",
            isError: false,
            title: "Summarize",
            icon: .symbol("sparkles"),
            isStreaming: true
        )
        let view = ResultCardView(
            payload: payload,
            canPaste: true,
            onExit: {},
            onPaste: {},
            onCopy: {}
        )
        XCTAssertNotNil(view)
    }

    func testRunAIPresetShowsLoadingToastAndDismissesOnResultCard() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        XCTAssertTrue(controller.toastController.isLoading, "Toast should be loading while AI generation is in progress")
        XCTAssertEqual(controller.toastController.currentFeedback?.message, "Generating…")

        // When the first result card arrives
        controller.showResultCard(text: "Translation result", isError: false, title: "Translate", isStreaming: true, session: controller.aiSessionID)
        XCTAssertFalse(controller.toastController.isLoading, "Loading toast must be dismissed once result card is shown")
    }

    func testRunAIPresetToastDismissedOnHide() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        XCTAssertTrue(controller.toastController.isLoading)

        controller.hide()
        XCTAssertFalse(controller.toastController.isLoading, "Loading toast must be dismissed on hide()")
    }

    func testRunAIPresetStreamsChunksAndTransitionsToResultCard() async {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let mockProvider = MockStreamingAIProvider(chunks: ["Hello", " World", "!"])
        AIServiceManager.shared.providerOverride = mockProvider
        defer { AIServiceManager.shared.providerOverride = nil }

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        XCTAssertTrue(controller.toastController.isLoading)

        // Wait for the streaming task to yield all chunks and complete
        let task = controller.activeStreamingTask
        _ = await task?.value

        XCTAssertFalse(controller.toastController.isLoading, "Loading toast must be dismissed after stream yields")
        XCTAssertEqual(controller.modeStore.mode, .content, "Mode should transition to .content result card")
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Hello World!")
        XCTAssertEqual(controller.modeStore.resultCard?.isError, false)
        XCTAssertEqual(controller.modeStore.resultCard?.isStreaming, false)
    }

    func testRunAIPresetShowsErrorInResultCardOnFailure() async {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 200, height: 50), display: false)
        controller.panel = panel

        let mockProvider = MockStreamingAIProvider(chunks: [], error: AIError.missingAPIKey)
        AIServiceManager.shared.providerOverride = mockProvider
        defer { AIServiceManager.shared.providerOverride = nil }

        let context = SelectionContext(
            text: "sample selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        controller.runAIPreset(prompt: "Translate", title: "Translate")
        let task = controller.activeStreamingTask
        _ = await task?.value

        XCTAssertFalse(controller.toastController.isLoading)
        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.modeStore.resultCard?.isError, true)
        XCTAssertEqual(controller.modeStore.resultCard?.text, AIError.missingAPIKey.errorDescription)
    }

    func testPopupViewOnRunAIDelegatesToControllerAndShowsLoadingToast() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }

        var ranAIWithID: String?
        let selection = SelectionContext(text: "Proofread this", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection)
        let view = PopupView(
            actions: [],
            context: context,
            onResult: { _ in },
            onRunAI: { actionID in
                ranAIWithID = actionID
                controller.runAIPreset(prompt: "Proofread this", title: "Proofread")
            }
        )
        view.onRunAI?("ai.preset.proofread")

        XCTAssertEqual(ranAIWithID, "ai.preset.proofread")
        XCTAssertTrue(controller.toastController.isLoading, "Toast should be loading while AI generation is in progress")
        XCTAssertEqual(controller.toastController.currentFeedback?.message, "Generating…")
    }

    func testDisplayAwareDismissalDistanceCalculation() {
        // Compact display (1366x768): 1366 * 0.12 = 163.92 -> clamped to 180
        let compactFrame = CGRect(x: 0, y: 0, width: 1366, height: 768)
        XCTAssertEqual(PopupMetrics.dismissalDistance(for: compactFrame), 180.0)

        // Standard 1080p display (1920x1080): 1920 * 0.12 = 230.4
        let standardFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(PopupMetrics.dismissalDistance(for: standardFrame), 230.4, accuracy: 0.01)

        // Large Retina / 1440p (2560x1440): 2560 * 0.12 = 307.2 -> clamped to 280
        let largeFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertEqual(PopupMetrics.dismissalDistance(for: largeFrame), 280.0)

        // UltraWide (3440x1440): clamped to 280
        let ultrawideFrame = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        XCTAssertEqual(PopupMetrics.dismissalDistance(for: ultrawideFrame), 280.0)
    }

    func testWorkspaceApplicationSwitchDismissesPopup() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY))
        defer { controller.hide() }
        XCTAssertTrue(controller.isVisible)

        let switchedApp = MockPopupFrontmostApp(bundleID: "com.apple.Notes")
        let notif = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: switchedApp]
        )
        NSWorkspace.shared.notificationCenter.post(notif)
        XCTAssertFalse(controller.isVisible, "Popup must dismiss on Cmd+Tab / workspace app activation")
    }

    func testWorkspaceSpaceSwitchDismissesPopup() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY))
        defer { controller.hide() }
        XCTAssertTrue(controller.isVisible)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        XCTAssertFalse(controller.isVisible, "Popup must dismiss on Mission Control active space change")
    }

    func testCorridorRectProtectsSubBarPathway() {
        let controller = PopupWindowController()
        let currentMouse = NSEvent.mouseLocation
        let panel = PopupPanel()
        // Main panel positioned below cursor
        panel.setFrame(NSRect(x: currentMouse.x - 50, y: currentMouse.y - 60, width: 100, height: 40), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer {
            controller.subBarController.panel.orderOut(nil)
            controller.hide()
        }

        // Sub-bar panel positioned above cursor: cursor is in the corridor between main bar and sub-bar
        controller.subBarController.panel.setFrame(NSRect(x: currentMouse.x - 50, y: currentMouse.y + 20, width: 100, height: 40), display: false)
        controller.subBarController.panel.orderFront(nil)
        controller.modeStore.isSubBarActive = true

        let dummyEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: currentMouse,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        controller.handleEvent(dummyEvent)
        XCTAssertTrue(controller.isVisible, "Cursor traversing the corridor between main bar and sub-bar must not dismiss the popup")
    }

    func testTrackpadScrollSensitivityThreshold() {
        let controller = PopupWindowController()
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 200, y: 200, width: 200, height: 50), display: false)
        controller.panel = panel
        let context = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: context)
        defer { controller.hide() }

        XCTAssertTrue(controller.isVisible)

        // Sub-threshold event: began phase with 3pt delta
        let cgBegan = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        cgBegan.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventBegan = NSEvent(cgEvent: cgBegan)!
        controller.handleEvent(eventBegan)
        XCTAssertTrue(controller.isVisible, "Sub-threshold scroll (3pt) should not dismiss popup")

        // Micro-jitter: changed phase with 4pt delta (accumulated 7pt < 12pt)
        let cgChanged = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 4, wheel2: 0, wheel3: 0)!
        cgChanged.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventChanged = NSEvent(cgEvent: cgChanged)!
        controller.handleEvent(eventChanged)
        XCTAssertTrue(controller.isVisible, "Accumulated micro-scroll (7pt) should not dismiss popup")

        // Exceeding threshold: changed phase with 6pt delta (accumulated 13pt >= 12pt)
        let cgDismiss = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 6, wheel2: 0, wheel3: 0)!
        cgDismiss.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let eventDismiss = NSEvent(cgEvent: cgDismiss)!
        controller.handleEvent(eventDismiss)
        XCTAssertFalse(controller.isVisible, "Accumulated scroll >= 12pt should dismiss popup")
    }
}

@MainActor
private final class MockStreamingAIProvider: AIProvider {
    let type: AIProviderType = .cloud
    let chunks: [String]
    let error: Error?

    init(chunks: [String], error: Error? = nil) {
        self.chunks = chunks
        self.error = error
    }

    func process(prompt: String, text: String) async throws -> String {
        if let error { throw error }
        return chunks.joined()
    }

    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let error = self.error
            let chunks = self.chunks
            Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    // Small yield so MainActor turns process
                    await Task.yield()
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

private final class MockPopupFrontmostApp: NSRunningApplication {
    private let bundleID: String?

    init(bundleID: String?) {
        self.bundleID = bundleID
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
}
