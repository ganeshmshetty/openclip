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
    
    internal func start() {
        let trusted = AXIsProcessTrusted()
        NSLog("[OpenClip] starting monitor, AX trusted: %d", trusted ? 1 : 0)
        if !trusted {
            showAccessibilityAlert()
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let app = NSWorkspace.shared.frontmostApplication else {
                NSLog("[OpenClip] mouseUp: no frontmost app")
                return
            }
            let cursor = NSEvent.mouseLocation
            NSLog("[OpenClip] mouseUp at (%.1f, %.1f) in %@", cursor.x, cursor.y, app.bundleIdentifier ?? "unknown")
            let capturedApp = app
            Task { @MainActor in
                self?.handleMouseUp(app: capturedApp, cursor: cursor)
            }
        }
        if monitor == nil {
            NSLog("[OpenClip] ERROR: global event monitor failed to register (AX denied?)")
        } else {
            NSLog("[OpenClip] global event monitor registered OK")
        }
    }
    
    internal func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    private func handleMouseUp(app: NSRunningApplication, cursor: CGPoint) {
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(Constants.filterDelay * 1_000_000_000))
            } catch {
                return
            }
            
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                NSLog("[OpenClip] filtered out %@", bundleID)
                return
            }
            
            let policy = RuleEngine.shared.resolvePolicies(for: app.bundleIdentifier ?? "")
            if policy.denyProbe || policy.denyPreprobe {
                NSLog("[OpenClip] denyProbe for %@", app.bundleIdentifier ?? "")
                return
            }
            
            NSLog("[OpenClip] retrieving text for %@", app.bundleIdentifier ?? "")
            // The retriever runs its own logic (which could be non-isolated) 
            if let text = await self.retriever.retrieveText(for: app, policy: policy) {
                NSLog("[OpenClip] got text len=%d, firing onSelection", text.count)
                if text.utf8.count <= Constants.maxTextLength {
                    let context = SelectionContext(
                        text: text,
                        sourceApp: app,
                        cursorPosition: cursor,
                        timestamp: Date(),
                        appPolicy: policy
                    )
                    self.onSelection?(context)
                }
            } else {
                NSLog("[OpenClip] no text retrieved")
            }
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "OpenClip needs Accessibility access to detect text selections. Please enable it in System Settings → Privacy & Security → Accessibility, then restart OpenClip."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
