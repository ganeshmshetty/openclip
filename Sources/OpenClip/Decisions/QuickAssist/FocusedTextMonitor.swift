// FocusedTextMonitor.swift
// OpenClip
//
// Watches the text of whatever field has keyboard focus, in any app, through the Accessibility
// APIs. This is the text source behind Quick Assist: `onText` fires with the field's contents
// whenever they change.
//
// Two mechanisms feed the same handler because neither is sufficient alone. `AXObserver`
// notifications (focus moved, value changed) are instant but plenty of apps never post
// kAXValueChangedNotification for their text views; a slow poll of the focused element catches
// those. Identical text is dropped, so the poll costs one AX read and nothing downstream.
//
// Privacy: secure fields (password inputs) are skipped by subrole, OpenClip's own windows are
// never read, and the text only ever reaches the configured Decision provider — locally, when that
// provider is Laya. Nothing is stored.
import AppKit
import ApplicationServices
import Core

@MainActor
public final class FocusedTextMonitor: ObservableObject {
    public static let shared = FocusedTextMonitor()

    /// Called with the focused field's text each time it changes. Main actor.
    public var onText: ((String) -> Void)?

    @Published public private(set) var isMonitoring = false
    /// Bundle id of the app whose field is being read, for the Quick Assist window's subtitle.
    @Published public private(set) var focusedAppName: String?

    /// How often the focused element is re-read as a backstop for apps that post no value-changed
    /// notification. One AX call; identical text is discarded before anything else runs.
    public var pollInterval: TimeInterval = 0.5

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedElement: AXUIElement?
    private var activationObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    private var lastText: String?

    /// Roles whose value is the text the user is editing. Anything else (buttons, rows, the
    /// window itself) is ignored so the monitor never reads a label or a whole document tree.
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        kAXSearchFieldSubrole as String,
    ]

    /// Accessibility must be granted before any of this works.
    public nonisolated var isAvailable: Bool { AXIsProcessTrusted() }

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isMonitoring, isAvailable else { return }
        isMonitoring = true
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self, let app else { return }
                self.attach(to: app)
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            attach(to: front)
        }
        startPolling()
        Log.decisions.info("Quick Assist focus monitoring started")
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        detach()
        lastText = nil
        focusedAppName = nil
        Log.decisions.info("Quick Assist focus monitoring stopped")
    }

    // MARK: - Attaching to an app

    private func attach(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            // Focus moved into OpenClip itself (Settings, the popup): keep the last reading.
            return
        }
        guard pid != observedPID else { return }
        detach()

        var created: AXObserver?
        guard AXObserverCreate(pid, focusedTextMonitorCallback, &created) == .success, let created else { return }
        observer = created
        observedPID = pid
        focusedAppName = app.localizedName

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)

        refreshFocusedElement()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            if let observedElement {
                AXObserverRemoveNotification(observer, observedElement, kAXValueChangedNotification as CFString)
            }
        }
        observer = nil
        observedPID = nil
        observedElement = nil
    }

    /// Re-reads the system-wide focused element and subscribes to its value changes.
    private func refreshFocusedElement() {
        guard let observer else { return }
        if let observedElement {
            AXObserverRemoveNotification(observer, observedElement, kAXValueChangedNotification as CFString)
        }
        observedElement = nil

        guard let element = Self.systemFocusedElement() else { return }
        observedElement = element
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon)
        readAndPublish(from: element)
    }

    // MARK: - Reading

    /// An AX notification arrived. The element it carried is deliberately not passed across the
    /// isolation hop (`AXUIElement` is not Sendable, and a stale one is worse than useless): the
    /// focused element is re-resolved here instead.
    fileprivate func handle(notification: String) {
        if notification == kAXFocusedUIElementChangedNotification as String {
            refreshFocusedElement()
        } else if let element = observedElement ?? Self.systemFocusedElement() {
            readAndPublish(from: element)
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? 0.5
                try? await Task.sleep(nanoseconds: UInt64(max(0.1, interval) * 1_000_000_000))
                guard let self, !Task.isCancelled, self.isMonitoring else { return }
                // The focused element can change without a notification (a new window, a sheet),
                // so re-resolve it rather than trusting the cached one.
                if let element = Self.systemFocusedElement() {
                    self.readAndPublish(from: element)
                }
            }
        }
    }

    private func readAndPublish(from element: AXUIElement) {
        guard let text = Self.editableText(of: element) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastText else { return }
        lastText = trimmed
        onText?(trimmed)
    }

    /// The system-wide focused UI element, or nil when nothing is focused.
    static func systemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let value = focused else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The text of an editable, non-secure text element; nil for anything else.
    static func editableText(of element: AXUIElement) -> String? {
        guard let role = copyString(element, kAXRoleAttribute) else { return nil }
        // A password field must never be read, whatever its role says.
        if let subrole = copyString(element, kAXSubroleAttribute) {
            if subrole == kAXSecureTextFieldSubrole as String { return nil }
            if textRoles.contains(subrole) { return copyString(element, kAXValueAttribute) }
        }
        guard textRoles.contains(role) else { return nil }
        return copyString(element, kAXValueAttribute)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// C callback for `AXObserver`: recovers the monitor from `refcon` and hops to the main actor.
/// The observer's run loop source is installed on the main run loop, so this already runs there.
private func focusedTextMonitorCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // Only Sendable values cross the hop: the notification name as a String, and the monitor
    // itself (a @MainActor class). The element is re-resolved on the other side.
    let name = notification as String
    let monitor = Unmanaged<FocusedTextMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handle(notification: name)
    }
}
