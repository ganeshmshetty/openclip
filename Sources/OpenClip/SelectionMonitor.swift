import AppKit

@MainActor
public final class SelectionMonitor {
    private var monitor: Any?
    private var debounceTask: Task<Void, Never>?
    private let retriever: any TextRetrieving
    
    public init(retriever: any TextRetrieving) {
        self.retriever = retriever
    }
    
    public func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let app = NSWorkspace.shared.frontmostApplication else { return }
            let cursor = event.locationInWindow
            let capturedApp = app
            
            Task { @MainActor in
                self?.handleMouseUp(app: capturedApp, cursor: cursor)
            }
        }
    }
    
    public func stop() {
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
                return
            }
            
            // The retriever runs its own logic (which could be non-isolated) 
            if let text = await self.retriever.retrieveText(for: app) {
                if text.utf8.count <= Constants.maxTextLength {
                    let context = SelectionContext(
                        text: text,
                        sourceApp: app,
                        cursorPosition: cursor,
                        timestamp: Date()
                    )
                    print("SelectionContext:", context)
                }
            }
        }
    }
}
