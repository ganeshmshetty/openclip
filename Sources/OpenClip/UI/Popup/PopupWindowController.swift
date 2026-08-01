import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var aiPanel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    
    private var isMenuTracking = false
    
    public init() { }
    
    public func show(for context: SelectionContext) {
        isMenuTracking = false
        currentContext = context
        
        var modifiers: ModifierFlags = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        
        let actionContext = ActionContext(selection: context, modifiers: modifiers)
        let availableActions = ActionCoordinator.shared.resolveActions(for: actionContext)
        
        let panel = self.panel ?? PopupPanel()
        self.panel = panel

        // Pre-compute card direction from real screen position
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let tempFrame = PopupPositioner.calculateFrame(
            for: context, popupSize: CGSize(width: 320, height: 54), in: screenBounds)
        let cardAbove = tempFrame.minY < screenBounds.minY + 280

        let rootView = PopupView(
            actions: availableActions,
            context: actionContext,
            initialAICardAboveBar: cardAbove,
            onResult: { [weak self] result in
                if case .showServices = result {
                    self?.handleResult(result)
                } else {
                    self?.handleResult(result)
                    self?.hide()
                }
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onAIStateChange: { [weak self] active, _ in
                self?.isAIOverlayActive = active
                // AI panel is dismissed only by explicit user actions (close/copy/replace) or hide()
            },
            onAIResult: { [weak self] text, isError in
                self?.showAIPanel(text: text, isError: isError, cardAbove: cardAbove)
            },
            onAIDismiss: { [weak self] in
                self?.hideAIPanel()
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
        
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)
        positionPanel(panel, size: size, for: context)
        panel.makeKeyAndOrderFront(nil)
        
        setupMonitors()
    }

    // MARK: - AI Overlay Panel

    private func showAIPanel(text: String, isError: Bool, cardAbove: Bool) {
        guard let panel else { return }

        hideAIPanel()
        let ap = PopupPanel()
        self.aiPanel = ap

        let aiView = AIResultOverlayView(
            resultText: text,
            isError: isError,
            onReplace: { [weak self] in
                self?.handleResult(.paste(text))
                self?.hide()
            },
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self?.hideAIPanel()
            },
            onClose: { [weak self] in
                self?.hideAIPanel()
            }
        )
        ap.contentView = NSHostingView(rootView: aiView)
        ap.contentView?.layoutSubtreeIfNeeded()

        let aiSize = sanitizedAISize(ap.contentView?.fittingSize)
        let gap: CGFloat = 8
        let barFrame = panel.frame

        let x = barFrame.origin.x
        let y: CGFloat
        if cardAbove {
            // Place card ABOVE bar — position its bottom edge just above bar's top
            y = barFrame.maxY + gap
        } else {
            // Place card BELOW bar — position its top edge just below bar's bottom
            y = barFrame.minY - aiSize.height - gap
        }

        ap.setFrame(CGRect(x: x, y: y, width: max(aiSize.width, barFrame.width), height: aiSize.height), display: true)
        ap.makeKeyAndOrderFront(nil)
    }

    private func hideAIPanel() {
        aiPanel?.orderOut(nil)
        aiPanel = nil
    }

    private func sanitizedAISize(_ raw: CGSize?) -> CGSize {
        var s = raw ?? CGSize(width: 320, height: 150)
        if s.width < 200 { s.width = 320 }
        if s.height < 60 { s.height = 150 }
        return s
    }


    /// Resize the bar-only panel, keeping the bar's top (maxY) fixed so it doesn't jump.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        let size = sanitizedPopupSize(proposedSize)
        let current = panel.frame.size
        if abs(current.width - size.width) < 1, abs(current.height - size.height) < 1 { return }
        // Bar-only panel: keep maxY fixed, resize downward (though height rarely changes now)
        let newOriginY = panel.frame.maxY - size.height
        panel.setFrame(CGRect(x: panel.frame.origin.x, y: newOriginY,
                              width: size.width, height: size.height), display: true)
    }

    private func sanitizedPopupSize(_ raw: CGSize?) -> CGSize {
        var size = raw ?? CGSize(width: 300, height: 54)
        if size.width < 100 { size.width = 300 }
        if size.height < 30 { size.height = 54 }
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
        hideAIPanel()
        panel?.orderOut(nil)
        removeMonitors()
        currentContext = nil
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
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .scrollWheel, .keyDown]) { [weak self] event in
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
    private var aiCardAboveBar: Bool = false

    private func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }
        
        switch event.type {
        case .mouseMoved:
            updatePopupHover(at: NSEvent.mouseLocation)
            let cursorLoc = NSEvent.mouseLocation
            // Only auto-dismiss by distance if AI overlay is not showing
            if aiPanel == nil, let panel = panel {
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
            let inAI = aiPanel?.frame.contains(clickLoc) ?? false
            if !inBar && !inAI {
                hide()
            }
        case .scrollWheel:
            if aiPanel == nil {
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
    
    private func handleResult(_ result: ActionResult) {
        switch result {
        case .simulatePaste:
            simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand) // Cmd+V
        case .showServices(let text):
            let picker = NSSharingServicePicker(items: [text])
            if let panel = panel, let view = panel.contentView {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        case .cut(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            simulateKeyShortcut(keyCode: Constants.deleteVirtualKey, modifier: []) // Delete
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .paste(let text):
            let pasteboard = NSPasteboard.general
            let copyToClipboard = UserDefaults.standard.bool(forKey: "completionCopyToClipboard")
            
            if copyToClipboard {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand) // Cmd+V
            } else {
                let savedItems = backupPasteboard(pasteboard)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand) // Cmd+V
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms delay for target app to read paste
                    self.restorePasteboard(pasteboard, items: savedItems)
                }
            }
        case .success, .failure, .none:
            break
        }
    }
    
    private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
    
    private func simulateKeyShortcut(keyCode: CGKeyCode, modifier: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        let flags = CGEventFlags(rawValue: modifier.rawValue | 0x000008)
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keydown.flags = flags
            keyup.flags = flags
            keydown.post(tap: .cgSessionEventTap)
            keyup.post(tap: .cgSessionEventTap)
        }
    }
}
