import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    
    public init() { }
    
    public func show(for context: SelectionContext) {
        // If the context is different, or it's a new selection, we show it
        currentContext = context
        
        let actionContext = ActionContext(selection: context, modifiers: [])
        let availableActions = ActionRegistry.shared.availableActions(for: actionContext)
        
        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        
        let rootView = PopupView(actions: availableActions, context: actionContext) { [weak self] in
            self?.hide()
        }
        panel.contentView = NSHostingView(rootView: rootView)
        
        let size = panel.contentView?.fittingSize ?? CGSize(width: 150, height: 50)
        let screen = NSScreen.screens.first { $0.frame.contains(context.cursorPosition) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        
        let frame = PopupPositioner.calculateFrame(
            for: context.cursorPosition,
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
    }
    
    private func setupMonitors() {
        removeMonitors()
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .mouseMoved, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(appDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
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
        switch event.type {
        case .mouseMoved:
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
        case .keyDown:
            if event.keyCode == 53 { // Escape
                hide()
            }
        default:
            break
        }
    }
    
    @objc private func appDidDeactivate() {
        hide()
    }
}
