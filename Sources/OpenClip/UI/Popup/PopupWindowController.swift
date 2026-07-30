import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    private var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    private var initialCursorPosition: CGPoint?
    
    public init() { }
    
    public func show(for context: SelectionContext) {
        // If the context is different, or it's a new selection, we show it
        currentContext = context
        initialCursorPosition = NSEvent.mouseLocation
        
        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        
        let rootView = PopupView()
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
        initialCursorPosition = nil
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
            if let initial = initialCursorPosition {
                let currentCursor = NSEvent.mouseLocation
                let distance = hypot(currentCursor.x - initial.x, currentCursor.y - initial.y)
                if distance > 40 {
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
            hide()
        default:
            break
        }
    }
    
    @objc private func appDidDeactivate() {
        hide()
    }
}
