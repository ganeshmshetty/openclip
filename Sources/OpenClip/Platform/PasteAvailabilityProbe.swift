// PasteAvailabilityProbe.swift
// OpenClip
//
// Determines whether an application supports paste by reading Edit ▸ Paste through
// Accessibility, delegating underlying inspection to OpenSelection.
import AppKit
import ApplicationServices
import Core
import OpenSelection

public protocol PasteAvailabilityProbing: Sendable {
    /// Determines whether the given application supports paste under the active app policy.
    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool?
}

public struct PasteAvailabilityProbe: PasteAvailabilityProbing {
    public typealias Lookup = @Sendable (_ pid: pid_t, _ deadline: Date?) -> Bool?

    private let inner: OpenSelection.PasteAvailabilityProbe

    /// Creates a probe instance using OpenSelection menu bar inspection and default timeout.
    public init() {
        self.inner = OpenSelection.PasteAvailabilityProbe(
            configuration: SelectionConfiguration(
                axReadTimeout: Constants.axReadTimeout,
                pasteProbeTimeout: Constants.pasteProbeTimeout,
                pasteProbeMaxConcurrent: Constants.pasteProbeMaxConcurrent
            )
        )
    }

    /// Testing initializer allowing callers to supply a pid-only lookup closure and custom timeout.
    init(lookup: @escaping @Sendable (pid_t) -> Bool?, timeout: TimeInterval = Constants.pasteProbeTimeout) {
        self.inner = OpenSelection.PasteAvailabilityProbe(
            lookup: lookup,
            timeout: timeout,
            maxConcurrent: Constants.pasteProbeMaxConcurrent
        )
    }

    /// Testing initializer allowing callers to supply a deadline-aware lookup closure and custom timeout.
    init(lookupWithDeadline lookup: @escaping Lookup, timeout: TimeInterval = Constants.pasteProbeTimeout) {
        self.inner = OpenSelection.PasteAvailabilityProbe(
            lookupWithDeadline: lookup,
            timeout: timeout,
            maxConcurrent: Constants.pasteProbeMaxConcurrent
        )
    }

    /// Determines whether the target application can paste, consulting policy overrides first.
    @MainActor
    public func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        if !PasteAvailability.needsProbe(policy: policy) {
            return PasteAvailability.effective(policy: policy, probe: nil)
        }
        guard PermissionManager.shared.isAccessibilityGranted,
              let app, app.isTerminated == false else { return nil }
        let pid = app.processIdentifier
        return PasteAvailability.effective(policy: policy, probe: await probePaste(pid: pid))
    }

    public nonisolated func probePaste(pid: pid_t) async -> Bool? {
        await inner.probePaste(pid: pid)
    }

    /// This function returns true if the menu item is Paste.
    public nonisolated static func isPaste(title: String?, cmdChar: String?, cmdCharModifiers: UInt?) -> Bool {
        OpenSelection.PasteAvailabilityProbe.isPaste(title: title, cmdChar: cmdChar, cmdCharModifiers: cmdCharModifiers)
    }
}
