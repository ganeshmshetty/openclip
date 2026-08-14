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
                let isSelectAll = Self.isSelectAllKey(keyCode: event.keyCode, flags: event.modifierFlags)
                self?.handleSelectionTrigger(isSelectAll: isSelectAll)
            }
        }
    }
    
    internal func stop() {
        debounceTask?.cancel()
        debounceTask = nil
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
    
    /// True when a key event is a selection gesture OpenClip should retrieve: ⌘A (select all) or an
    /// arrow key with Shift held (⇧/⌥⇧/⌘⇧+arrow extend/collapse selection). Only the select-all
    /// gesture requires the exact `.command` set; arrow gestures fire whenever `.shift` is held with
    /// optional `.option`/`.command`, so plain typing and unrelated shortcuts still don't match.
    /// Persistent/non-gesture flags (`.capsLock`
    /// is held in every keyDown's modifierFlags while caps lock is engaged; `.function`, `.numericPad`,
    /// `.help` are device/hardware bits) are stripped before comparing.
    internal static func isSelectionTrigger(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let gestureFlags = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad, .help])
        if gestureFlags == .command {
            return keyCode == selectAllKeyCode
        }
        if gestureFlags.contains(.shift) && gestureFlags.isSubset(of: [.shift, .option, .command]) {
            return arrowKeyCodes.contains(keyCode)
        }
        return false
    }

    /// True only for the exact ⌘A (select-all) gesture, using the same flag normalization as
    /// `isSelectionTrigger`.
    private static func isSelectAllKey(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let gestureFlags = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad, .help])
        return gestureFlags == .command && keyCode == selectAllKeyCode
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
            let result = await SelectionRetrievalCoordinator().retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current
            )
            if Task.isCancelled { return }
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
    
    /// Keyboard selection gesture: retrieve under the frontmost app resolved *after* the debounce
    /// (a ⌘A/⇧+arrow in one app followed by a switch during the debounce window must target the
    /// now-frontmost app). `isSelectAll` marks a ⌘A select-all, which copy-based retrieval modes
    /// reject unless the focused element is text-bearing (row selection in Finder/Mail/table views).
    internal func handleSelectionTrigger(isSelectAll: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(Constants.keyboardSelectionDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            if Task.isCancelled { return }

            guard let app = NSWorkspace.shared.frontmostApplication else { return }

            if let bundleID = app.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
                return
            }
            
            let policy = RuleEngine.shared.resolvePolicies(for: app.bundleIdentifier ?? "")
            let appIdentity = AppIdentity(app)
            let probeTask = self.preparePasteProbe?(app, policy)
            let result = await SelectionRetrievalCoordinator().retrieve(
                for: appIdentity,
                policy: policy,
                cursor: CursorClassifier.current,
                isSelectAll: isSelectAll
            )
            if Task.isCancelled { return }
            // For keyboard selections the mouse may be anywhere, so anchor the popup on the
            // selection's accessibility bounds (converted to Cocoa screen coordinates) when the
            // retrieval produced them, falling back to the mouse location otherwise.
            let anchor = result?.bounds.map {
                Self.cocoaPoint(fromAXPoint: CGPoint(x: $0.minX, y: $0.minY))
            } ?? NSEvent.mouseLocation
            await self.deliverSelection(
                result: result,
                appIdentity: appIdentity,
                policy: policy,
                cursor: anchor,
                mouseDownLocation: nil,
                probeTask: probeTask
            )
        }
    }
    
    /// Converts an accessibility-coordinate point (primary-display origin at the top-left, y
    /// growing downward) into Cocoa screen coordinates (origin at the bottom-left).
    private static func cocoaPoint(fromAXPoint point: CGPoint) -> CGPoint {
        guard let main = NSScreen.main else { return point }
        return CGPoint(x: point.x, y: main.frame.maxY - point.y)
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
        guard !Task.isCancelled else { return }
        guard let result,
              TextSanitizer.isSubstantial(result.text),
              result.text.utf8.count <= Constants.maxTextLength else { return }
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
        guard !Task.isCancelled else { return }
        self.onSelection?(context, canPaste)
    }
}