import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    
    private var isMenuTracking = false
    
    public init() { }
    
    public func show(for context: SelectionContext) {
        isMenuTracking = false
        // If the context is different, or it's a new selection, we show it
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
        
        let rootView = PopupView(actions: availableActions, context: actionContext) { [weak self] result in
            if case .showServices = result {
                self?.handleResult(result)
            } else {
                self?.handleResult(result)
                self?.hide()
            }
        }
        panel.contentView = NSHostingView(rootView: rootView)
        
        // Force a layout pass so fittingSize reflects actual content
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? CGSize(width: 300, height: 54)
        if size.width < 100 { size.width = 300 }
        if size.height < 30 { size.height = 54 }
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(
            for: context,
            popupSize: size,
            in: screenBounds
        )
        
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        
        setupMonitors()
    }
    
    public func hide() {
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
    
    private func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }
        
        switch event.type {
        case .mouseMoved:
            updatePopupHover(at: NSEvent.mouseLocation)
            if let panel = panel {
                let currentCursor = NSEvent.mouseLocation
                let frame = panel.frame
                let dx = max(0, max(frame.minX - currentCursor.x, currentCursor.x - frame.maxX))
                let dy = max(0, max(frame.minY - currentCursor.y, currentCursor.y - frame.maxY))
                let distance = hypot(dx, dy)
                if distance > Constants.popupDismissalDistance {
                    hide()
                }
            }
        case .leftMouseDown:
            if let panel = panel {
                let clickLocation = NSEvent.mouseLocation
                if !panel.frame.contains(clickLocation) {
                    hide()
                }
            }
        case .scrollWheel:
            hide()
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
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand) // Cmd+V
        case .success, .failure, .none:
            break
        }
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
