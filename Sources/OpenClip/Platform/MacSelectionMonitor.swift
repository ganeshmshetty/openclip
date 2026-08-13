// MacSelectionMonitor.swift
// OpenClip
//
// Monitors macOS mouse and keyboard events to detect text selection actions and trigger OpenClip popup presentation.
import AppKit
import Core

@MainActor
internal final class MacSelectionMonitor: SelectionMonitoring {
    /// Selection context + the paste-availability probe result for the source app (`nil` when the
    /// app is excluded or the probe never ran).
    internal var onSelection: ((SelectionContext, Bool?) -> Void)?
    /// Starts the paste-availability probe for a target app (rules + AX) in parallel with selection
    /// retrieval so the popup can apply the result on its first frame. Wired to the popup controller
    /// by the composition root (AppDelegate).
    internal var preparePasteProbe: ((NSRunningApplication, AppPolicyContext) -> Task<Bool?, Never>?)?
    
    private var monitor: Any?
    private var keyDownMonitor: Any?
    internal var debounceTask: Task<Void, Never>?
    private var mouseDownMonitor: Any?
    private var mouseDownLocation: CGPoint?
    
    /// Key codes (ANSI/QWERTY) that signal a selection gesture worth retrieving.
    private static let selectAllKeyCode: UInt16 = 0x00      // kVK_ANSI_A
    private static let arrowKeyCodes: Set<UInt16> = [0x7B, 0x7C, 0x7D, 0x7E]  // left/right/down/up
    
    internal init() {}
    
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
        
        // Keyboard selection gestures (⌘A select-all, ⇧+arrow extend/collapse) trigger the same
        // retrieval path as a mouse drag, so keyboard-only selections surface the popup too.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard Self.isSelectionTrigger(keyCode: event.keyCode, flags: event.modifierFlags) else { return }
                self?.handleSelectionTrigger()
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
        if let keyDownMonitor = keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }
    
    // MARK: - Trigger detection
    
    /// True when a key event is a selection gesture OpenClip should retrieve: ⌘A (select all) or
    /// ⇧+arrow (extend/collapse selection). Only the exact modifier set matches, so plain typing and
    /// app shortcuts that happen to use these keys don't fire. Persistent/non-gesture flags (`.capsLock`
    /// is held in every keyDown's modifierFlags while caps lock is engaged; `.function`, `.numericPad`,
    /// `.help` are device/hardware bits) are stripped before comparing.
    internal static func isSelectionTrigger(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let gestureFlags = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad, .help])
        if gestureFlags == .command {
            return keyCode == selectAllKeyCode
        }
        if gestureFlags == .shift {
            return arrowKeyCodes.contains(keyCode)
        }
        return false
    }
    
    // MARK: - Event handling
    
    private func handleMouseUp(app: NSRunningApplication, cursor: CGPoint, clickCount: Int) {
        let downPoint = mouseDownLocation
        mouseDownLocation = nil
        
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = RuleEngine.shared.resolvePolicies(for: app.bundleIdentifier ?? "")
            
            // Measure drag distance for click filtering
            var isDragOrMultiClick = clickCount >= 2
            if !isDragOrMultiClick, let downPoint {
                let dx = cursor.x - downPoint.x
                let dy = cursor.y - downPoint.y
                isDragOrMultiClick = (dx * dx + dy * dy) > 9.0 // > 3px movement
            }
            guard isDragOrMultiClick else { return }
            
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            // Direct AX check executed IMMEDIATELY (0ms delay) for instant smooth opening
            let result = await SelectionRetrievalCoordinator().retrieve(for: appIdentity, policy: policy)
            await self.deliverSelection(
                result: result,
                appIdentity: appIdentity,
                policy: policy,
                cursor: cursor,
                mouseDownLocation: downPoint,
                probeTask: probeTask
            )
        }
    }
    
    /// Keyboard selection gesture: retrieve under the current frontmost app (no click filtering).
    internal func handleSelectionTrigger() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(Constants.keyboardSelectionDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            if Task.isCancelled { return }

            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = RuleEngine.shared.resolvePolicies(for: app.bundleIdentifier ?? "")
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            let result = await SelectionRetrievalCoordinator().retrieve(for: appIdentity, policy: policy)
            if Task.isCancelled { return }
            await self.deliverSelection(
                result: result,
                appIdentity: appIdentity,
                policy: policy,
                cursor: NSEvent.mouseLocation,
                mouseDownLocation: nil,
                probeTask: probeTask
            )
        }
    }
    
    /// Shared post-retrieval assembly: build the length-gated SelectionContext and notify
    /// `onSelection` with the paste-probe result. Used by both the mouse and keyboard paths.
    private func deliverSelection(
        result: TextResult?,
        appIdentity: AppIdentity,
        policy: AppPolicyContext,
        cursor: CGPoint,
        mouseDownLocation: CGPoint?,
        probeTask: Task<Bool?, Never>?
    ) async {
        guard let result, result.text.utf8.count <= Constants.maxTextLength else { return }
        let context = SelectionContext(
            text: result.text,
            sourceApp: appIdentity,
            cursorPosition: cursor,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: result.bounds,
            timestamp: Date(),
            appPolicy: policy
        )
        let canPaste = await probeTask?.value
        self.onSelection?(context, canPaste)
    }
}