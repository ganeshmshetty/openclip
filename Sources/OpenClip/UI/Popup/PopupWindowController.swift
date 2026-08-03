// PopupWindowController.swift
// OpenClip
//
// Manages the window lifecycle, event tracking, positioning, and animation of the main floating popup panel.
// Also owns the reusable bubble panel (BubbleCardView) that renders hover info, result, and sub-action
// bubbles, plus the hover-debounce and long-press timers that trigger them per Action.gesturePolicy.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var bubblePanel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    private var currentActionContext: ActionContext?
    private var cardAbove = false

    private var hoverDebounceTask: Task<Void, Never>?
    private var longPressTask: Task<Void, Never>?
    private var hoveredAction: (any Action)?
    private var longPressFired = false
    /// Set true while a non-dismissable bubble (.result/.menu) is showing.
    private var bubbleBlocksDismiss = false

    private var isMenuTracking = false
    
    public init() { }
    
    public func show(for context: SelectionContext) {
        isMenuTracking = false
        currentContext = context
        
        let actionContext = ActionContext(selection: context, modifiers: [])
        currentActionContext = actionContext
        let availableActions = ActionCoordinator.shared.resolveActions(for: actionContext)
        
        let panel = self.panel ?? PopupPanel()
        self.panel = panel

        // Pre-compute card direction from real screen position
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let tempFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: CGSize(width: 320, height: 54), in: screenBounds)
        cardAbove = tempFrame.minY < screenBounds.minY + 280

        let rootView = PopupView(
            actions: availableActions,
            context: actionContext,
            initialAICardAboveBar: cardAbove,
            onResult: { [weak self] result in
                self?.handleResult(result)
                self?.hide()
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onAIStateChange: { [weak self] active, _ in
                self?.isAIOverlayActive = active
                // Bubble panel is dismissed only by explicit user actions or hide()
            },
            onAIResult: { [weak self] text, isError in
                self?.showAIBubble(text: text, isError: isError)
            },
            onAIDismiss: { [weak self] in
                self?.hideBubble()
            },
            onHoveredActionChanged: { [weak self] action in
                self?.updateHoveredAction(action)
            },
            onShowBubble: { [weak self] content in
                self?.showMenuBubble(content: content)
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)
        positionPanel(panel, size: size, for: context)
        panel.makeKeyAndOrderFront(nil)
        // Make the panel the key window so it receives keyDown through the local event monitor.
        // A nonactivating panel becoming key does not activate the app.
        panel.makeKey()
        
        setupMonitors()
    }

    // MARK: - Bubble Panel

    private func showBubble(content: BubbleContent, blocksDismiss: Bool, anchorX: CGFloat? = nil, onOutcome: @escaping (BubbleOutcome) -> Void, onClose: (() -> Void)? = nil) {
        guard let panel else { return }

        hideBubble()
        let bp = PopupPanel()
        self.bubblePanel = bp
        bubbleBlocksDismiss = blocksDismiss

        let bubbleView = BubbleCardView(
            content: content,
            onOutcome: { outcome in
                onOutcome(outcome)
            },
            onClose: onClose
        )
        bp.contentView = NSHostingView(rootView: bubbleView)
        bp.contentView?.layoutSubtreeIfNeeded()

        let bubbleSize = sanitizedBubbleSize(bp.contentView?.fittingSize)
        let gap: CGFloat = 8
        let barFrame = panel.frame

        // Horizontal: center on the anchor point (e.g. the pressed/hovered button) clamped to the
        // screen; fall back to aligning with the bar's left edge.
        let screen = NSScreen.screens.first { $0.frame.contains(barFrame.origin) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let padding: CGFloat = Constants.popupPadding
        // The panel is as wide as the wider of the bubble and the bar, so clamp by the final width.
        let finalWidth = max(bubbleSize.width, barFrame.width)
        var x: CGFloat
        if let anchorX {
            x = anchorX - finalWidth / 2
        } else {
            x = barFrame.origin.x
        }
        x = max(screenBounds.minX + padding, min(x, screenBounds.maxX - finalWidth - padding))

        var y: CGFloat
        if cardAbove {
            // Place bubble ABOVE bar — position its bottom edge just above bar's top
            y = barFrame.maxY + gap
        } else {
            // Place bubble BELOW bar — position its top edge just below bar's bottom
            y = barFrame.minY - bubbleSize.height - gap
        }
        // Clamp the final frame fully inside the screen so a tall menu bubble (no height bound)
        // never renders off-screen.
        y = max(screenBounds.minY + padding, min(y, screenBounds.maxY - bubbleSize.height - padding))

        bp.setFrame(CGRect(x: x, y: y, width: finalWidth, height: bubbleSize.height), display: true)
        bp.makeKeyAndOrderFront(nil)
    }

    /// Replaces the AI overlay with a BubbleCardView `.result` bubble.
    private func showAIBubble(text: String, isError: Bool) {
        let content = BubbleContent(
            title: isError ? "AI Error" : "AI Result",
            icon: isError ? "exclamationmark.triangle" : "sparkles",
            rows: [.text(text)],
            footer: isError ? [] : [
                BubbleOption(
                    title: "Replace",
                    icon: "arrow.triangle.2.circlepath",
                    outcome: .perform(.paste(text))
                ),
                BubbleOption(
                    title: "Copy",
                    icon: "doc.on.doc",
                    outcome: .perform(.copy(text))
                )
            ],
            emphasis: .result
        )

        showBubble(
            content: content,
            blocksDismiss: true,
            onOutcome: { [weak self] outcome in
                guard case .perform(let result) = outcome else { return }
                self?.handleResult(result)
                if case .paste = result {
                    self?.hide()
                } else {
                    self?.hideBubble()
                }
            },
            onClose: { [weak self] in
                self?.hideBubble()
            }
        )
    }

    /// Shows a sub-action `.menu` bubble (e.g. transform options) anchored near the current mouse position.
    private func showMenuBubble(content: BubbleContent) {
        showBubble(
            content: content,
            blocksDismiss: true,
            anchorX: NSEvent.mouseLocation.x,
            onOutcome: { [weak self] outcome in
                guard case .perform(let result) = outcome else { return }
                self?.handleResult(result)
                self?.hide()
            },
            onClose: { [weak self] in
                self?.hideBubble()
            }
        )
    }

    private func hideBubble() {
        bubblePanel?.orderOut(nil)
        bubblePanel = nil
        bubbleBlocksDismiss = false
    }

    private func sanitizedBubbleSize(_ raw: CGSize?) -> CGSize {
        var s = raw ?? CGSize(width: 300, height: 120)
        s.width = max(s.width, 160)
        s.height = max(s.height, 48)
        return s
    }

    // MARK: - Hover Info Bubble

    private func updateHoveredAction(_ action: (any Action)?) {
        // Re-entry with the same action id must not cancel a pending hover bubble for it.
        guard action?.id != hoveredAction?.id else { return }
        hoverDebounceTask?.cancel()
        hoveredAction = action

        guard let action, let actionContext = currentActionContext else {
            if bubbleBlocksDismiss == false {
                hideBubble()
            }
            return
        }

        guard action.gesturePolicy.hoverPreview else {
            // Never tear down a blocking (.result/.menu) bubble just because the pointer
            // crossed a bar button that has no hover preview.
            if bubbleBlocksDismiss == false {
                hideBubble()
            }
            return
        }

        hoverDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.bubbleHoverDelayNanoseconds)
            guard !Task.isCancelled,
                  self.hoveredAction?.id == action.id,
                  // A blocking bubble may have opened while we were debouncing; don't replace it.
                  self.bubbleBlocksDismiss == false else { return }

            let icon: String? = {
                if case .symbol(let name) = action.displayIcon { return name }
                return nil
            }()
            let line = await (action as? any PreviewProviding)?.previewLine(for: actionContext)

            let content = BubbleContent(
                title: action.displayTitle,
                icon: icon,
                subtitle: line ?? action.displayTitle,
                emphasis: .info
            )
            self.showBubble(content: content, blocksDismiss: false, anchorX: NSEvent.mouseLocation.x) { _ in }
        }
    }

    // MARK: - Long-Press Bubble

    private func beginLongPressIfNeeded(at clickLocation: CGPoint) {
        longPressTask?.cancel()
        longPressFired = false

        guard let hoveredAction, hoveredAction.gesturePolicy.longPress != nil,
              let actionContext = currentActionContext,
              let panel, panel.frame.contains(clickLocation) else { return }

        let targetAction = hoveredAction
        longPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.bubbleLongPressNanoseconds)
            guard !Task.isCancelled, self.hoveredAction?.id == targetAction.id else { return }
            guard let bubble = await (targetAction as? any ResultBubbleProviding)?.makeBubble(for: actionContext) else {
                return
            }
            guard !Task.isCancelled else { return }
            longPressFired = true
            self.showBubble(content: bubble, blocksDismiss: true, anchorX: clickLocation.x) { [weak self] outcome in
                guard case .perform(let result) = outcome else { return }
                self?.handleResult(result)
                self?.hide()
            } onClose: { [weak self] in
                self?.hideBubble()
            }
        }
    }
    
    // MARK: - Panel Resize

    /// Resize the bar-only panel, keeping the bar's top (maxY) fixed so it doesn't jump.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        var size = sanitizedPopupSize(proposedSize)
        if let screen = panel.screen {
            let maxWidth = max(0, screen.visibleFrame.width - Constants.popupPadding * 2)
            size.width = min(size.width, maxWidth)
        }
        let current = panel.frame.size
        if abs(current.width - size.width) < 1, abs(current.height - size.height) < 1 { return }
        // Bar-only panel: keep maxY fixed, resize downward (though height rarely changes now)
        let newOriginY = panel.frame.maxY - size.height
        panel.setFrame(CGRect(x: panel.frame.origin.x, y: newOriginY,
                              width: size.width, height: size.height), display: true)
    }

    private func sanitizedPopupSize(_ raw: CGSize?) -> CGSize {
        var size = raw ?? CGSize(width: 300, height: 54)
        size.width = max(size.width, 100)
        size.height = max(size.height, 30)
        return size
    }

    private func positionPanel(_ panel: PopupPanel, size: CGSize, for context: SelectionContext) {
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: size,
            in: screenBounds
        )
        panel.setFrame(frame, display: true)
    }
    
    public func hide() {
        isAIOverlayActive = false
        hideBubble()
        hoverDebounceTask?.cancel()
        longPressTask?.cancel()
        longPressTask = nil
        longPressFired = false
        panel?.orderOut(nil)
        removeMonitors()
        currentContext = nil
        currentActionContext = nil
        hoveredAction = nil
        isMenuTracking = false
        PopupHoverState.shared.location = nil
    }
    
    private func setupMonitors() {
        removeMonitors()

        let canMonitorGlobally = PermissionManager.shared.isAccessibilityGranted
        PopupHoverState.shared.usesGlobalMouseMonitoring = canMonitorGlobally
        if canMonitorGlobally {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
            }
        } else {
            print("[Popup] Accessibility permission unavailable; using local hover tracking.")
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
            if let self, event.type == .leftMouseUp {
                // A mouse-up always ends a pending long press: cancel the task so a quick click
                // doesn't later fire a result bubble, and swallow the trailing mouse-up only when
                // a long-press bubble was actually shown (so it doesn't also perform the action).
                self.longPressTask?.cancel()
                self.longPressTask = nil
                if self.longPressFired {
                    self.longPressFired = false
                    return nil
                }
            }
            self?.handleEvent(event)
            return event
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    @objc private func menuDidBeginTracking() {
        isMenuTracking = true
    }
    
    @objc private func menuDidEndTracking() {
        isMenuTracking = false
    }
    
    private func removeMonitors() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    private var isAIOverlayActive: Bool = false

    private func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }
        
        switch event.type {
        case .mouseMoved:
            updatePopupHover(at: NSEvent.mouseLocation)
            let cursorLoc = NSEvent.mouseLocation
            // Only auto-dismiss by distance when no dismiss-blocking bubble is showing
            if !bubbleBlocksDismiss, let panel = panel {
                let frame = panel.frame
                let dx = max(0, max(frame.minX - cursorLoc.x, cursorLoc.x - frame.maxX))
                let dy = max(0, max(frame.minY - cursorLoc.y, cursorLoc.y - frame.maxY))
                if hypot(dx, dy) > Constants.popupDismissalDistance {
                    hide()
                }
            }
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            let inBar = panel?.frame.contains(clickLoc) ?? false
            let inBubble = bubblePanel?.frame.contains(clickLoc) ?? false
            if inBar {
                beginLongPressIfNeeded(at: clickLoc)
            }
            if !inBar && !inBubble {
                hide()
            }
        case .scrollWheel:
            if !bubbleBlocksDismiss {
                hide()
            }
        case .keyDown:
            if event.keyCode == 53 { // Escape
                hide()
            }
        default:
            break
        }
    }

    private func updatePopupHover(at screenLocation: CGPoint) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else {
            PopupHoverState.shared.location = nil
            return
        }

        let windowPoint = panel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard contentView.bounds.contains(contentPoint) else {
            PopupHoverState.shared.location = nil
            return
        }

        NSCursor.arrow.set()
        let y = contentView.isFlipped ? contentPoint.y : contentView.bounds.height - contentPoint.y
        PopupHoverState.shared.location = CGPoint(x: contentPoint.x, y: y)
    }
    
    @objc private func appDidDeactivate() {
        if !isMenuTracking {
            hide()
        }
    }
    
    private let resultHandler: ActionResultHandler = DefaultActionResultHandler()

    private func handleResult(_ result: ActionResult) {
        Task { @MainActor in
            try? await resultHandler.handle(result, in: panel?.contentView)
        }
    }
}
