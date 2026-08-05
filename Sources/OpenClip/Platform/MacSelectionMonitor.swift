// MacSelectionMonitor.swift
// OpenClip
//
// Monitors macOS mouse and keyboard events to detect text selection actions and trigger OpenClip popup presentation.
import AppKit
import ApplicationServices
import Core

@MainActor
internal final class MacSelectionMonitor: SelectionMonitoring {
    internal var onSelection: ((SelectionContext) -> Void)?
    
    private var monitor: Any?
    private var debounceTask: Task<Void, Never>?
    private let retriever: any TextRetrieving
    
    internal init(retriever: any TextRetrieving) {
        self.retriever = retriever
    }
    
    private var mouseDownMonitor: Any?
    private var mouseDownLocation: CGPoint?
    
    internal func start() {
        guard monitor == nil else { return }
        
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            // Global monitors run on the main thread. Creating `Task { @MainActor in }` here
            // makes the compiler emit an executor-isolation check that crashes in
            // swift_task_isCurrentExecutorWithFlagsImpl after long uptime (known Swift 6 runtime
            // bug); MainActor.assumeIsolated avoids that path.
            MainActor.assumeIsolated {
                self?.mouseDownLocation = point
            }
        }
        
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let cursor = NSEvent.mouseLocation
            let clickCount = event.clickCount
            MainActor.assumeIsolated {
                self?.handleMouseUp(app: app, cursor: cursor, clickCount: clickCount)
            }
        }
    }
    
    internal func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let mouseDownMonitor = mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
    }
    
    private func handleMouseUp(app: NSRunningApplication, cursor: CGPoint, clickCount: Int) {
        let downPoint = mouseDownLocation
        mouseDownLocation = nil
        
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = RuleEngine.shared.resolvePolicies(for: app.bundleIdentifier ?? "")
            if policy.denyProbe || policy.denyPreprobe {
                return
            }
            
            // Measure drag distance for click filtering
            var isDragOrMultiClick = clickCount >= 2
            if !isDragOrMultiClick, let downPoint {
                let dx = cursor.x - downPoint.x
                let dy = cursor.y - downPoint.y
                isDragOrMultiClick = (dx * dx + dy * dy) > 9.0 // > 3px movement
            }
            guard isDragOrMultiClick else { return }
            
            let appIdentity = AppIdentity(app)
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            if let result = await self.retriever.retrieveTextResult(for: appIdentity, policy: policy) {
                let text = result.text
                if text.utf8.count <= Constants.maxTextLength {
                    let context = SelectionContext(
                        text: text,
                        sourceApp: appIdentity,
                        cursorPosition: cursor,
                        mouseDownLocation: downPoint,
                        selectionBounds: result.bounds,
                        timestamp: Date(),
                        appPolicy: policy
                    )
                    self.onSelection?(context)
                }
            }
        }
    }
}
