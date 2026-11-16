import AppKit
import ApplicationServices
import Core
import os

/// Off-main-thread, deadline-bounded AX probe that suppresses automatic synthetic `Cmd+C`
/// when focus is inside a keybinding-recording input widget (such as VS Code's Keyboard
/// Shortcuts "Recording Keys" box), preventing OpenClip from appending `cmd+c` to the
/// recorded shortcut.
internal struct AutomaticCopyTargetProbe: Sendable {
    struct AncestorNode: Equatable, Sendable {
        let role: String?
        let subrole: String?
        let title: String?
        let description: String?
        let domClasses: [String]
    }

    typealias Lookup = @Sendable (pid_t, Date) -> Bool

    private let lookup: Lookup
    private let timeout: TimeInterval
    private static let queue = DispatchQueue(label: "com.openclip.ax-autocopy-target", qos: .userInitiated, attributes: .concurrent)
    private static let inFlight = OSAllocatedUnfairLock(initialState: 0)

    private static let maxAncestorDepth = 10
    private static let axPlaceholderValueAttribute = "AXPlaceholderValue"
    private static let axDOMClassListAttribute = "AXDOMClassList"
    private static let monacoInputBoxClass = "monaco-inputbox"
    private static let syntheticFocusClass = "synthetic-focus"
    private static let searchContainerClass = "search-container"
    private static let applicationDialogSubrole = "AXApplicationDialog"
    private static let keyboardShortcutsTitle = "Keyboard Shortcuts"
    private static let recordingPlaceholderFragments = [
        "Recording Keys",
        "Press desired key combination"
    ]

    static let `default` = AutomaticCopyTargetProbe()

    init(timeout: TimeInterval = Constants.axReadTimeout, lookup: @escaping Lookup = Self.lookupKeyRecordingInput) {
        self.timeout = timeout
        self.lookup = lookup
    }

    func shouldSuppressCopy(pid: pid_t) async -> Bool {
        guard pid > 0, !Task.isCancelled else { return false }
        let acquired = Self.inFlight.withLock { count in
            guard count < Constants.axMaxConcurrentInspects else { return false }
            count += 1
            return true
        }
        guard acquired else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        let lookup = self.lookup
        let result = await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Bool) -> Void = { value in
                let won = resumed.withLock { settled in
                    guard !settled else { return false }
                    settled = true
                    return true
                }
                if won { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                finish(false)
            }
            Self.queue.async {
                defer { Self.inFlight.withLock { $0 -= 1 } }
                let matched = Date() < deadline && lookup(pid, deadline)
                finish(Date() < deadline && matched)
            }
        }
        return !Task.isCancelled && result
    }

    /// Pure classifier for unit tests and live AX snapshots.
    /// Requires `AXTextField` so main code editors (`AXTextArea`) are never matched.
    static func isKeyRecordingInput(
        focusedRole: String?,
        focusedPlaceholder: String?,
        ancestorNodes: [AncestorNode]
    ) -> Bool {
        guard focusedRole == kAXTextFieldRole else { return false }

        if let focusedPlaceholder,
           recordingPlaceholderFragments.contains(where: { focusedPlaceholder.localizedCaseInsensitiveContains($0) }) {
            return true
        }

        let hasSyntheticFocusInputBox = ancestorNodes.contains { node in
            node.domClasses.contains(monacoInputBoxClass) && node.domClasses.contains(syntheticFocusClass)
        }
        if hasSyntheticFocusInputBox {
            return true
        }

        let hasSearchContainer = ancestorNodes.contains { $0.domClasses.contains(searchContainerClass) }
        let inKeyboardShortcutsDialog = ancestorNodes.contains { node in
            node.subrole == applicationDialogSubrole &&
                (node.title == keyboardShortcutsTitle || node.description == keyboardShortcutsTitle)
        }
        return hasSearchContainer && inKeyboardShortcutsDialog
    }

    private static func lookupKeyRecordingInput(pid: pid_t, deadline: Date) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        guard let focused = elementAttribute(kAXFocusedUIElementAttribute, of: appElement, deadline: deadline) else {
            return false
        }
        guard let focusedRole = attribute(kAXRoleAttribute, of: focused, deadline: deadline) as? String,
              focusedRole == kAXTextFieldRole else {
            return false
        }
        let focusedPlaceholder = attribute(axPlaceholderValueAttribute, of: focused, deadline: deadline) as? String

        var ancestors: [AncestorNode] = []
        var current = elementAttribute(kAXParentAttribute, of: focused, deadline: deadline)
        while let element = current, ancestors.count < maxAncestorDepth, Date() < deadline {
            let role = attribute(kAXRoleAttribute, of: element, deadline: deadline) as? String
            let subrole = attribute(kAXSubroleAttribute, of: element, deadline: deadline) as? String
            let title = attribute(kAXTitleAttribute, of: element, deadline: deadline) as? String
            let desc = attribute(kAXDescriptionAttribute, of: element, deadline: deadline) as? String
            let domClasses = attribute(axDOMClassListAttribute, of: element, deadline: deadline) as? [String] ?? []
            ancestors.append(AncestorNode(
                role: role,
                subrole: subrole,
                title: title,
                description: desc,
                domClasses: domClasses
            ))
            current = elementAttribute(kAXParentAttribute, of: element, deadline: deadline)
        }

        return isKeyRecordingInput(
            focusedRole: focusedRole,
            focusedPlaceholder: focusedPlaceholder,
            ancestorNodes: ancestors
        )
    }

    private static func elementAttribute(_ name: String, of element: AXUIElement, deadline: Date) -> AXUIElement? {
        guard let value = attribute(name, of: element, deadline: deadline),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return value as! AXUIElement
    }

    private static func attribute(_ name: String, of element: AXUIElement, deadline: Date) -> CFTypeRef? {
        guard applyTimeout(to: element, deadline: deadline) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func applyTimeout(to element: AXUIElement, deadline: Date) -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        return AXUIElementSetMessagingTimeout(element, Float(remaining)) == .success
    }
}
