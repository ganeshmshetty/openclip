// PasteAvailabilityProbe.swift
// OpenClip
//
// Probes whether the frontmost app currently supports Paste (the Edit ▸ Paste menu item is enabled)
// via Accessibility, mirroring the `SelectionRetrievalCoordinator.pressEditCopyMenu` menu-bar walk.
// When AX is unavailable, or the probe times out, it reports "unknown" — callers treat that as
// cannot-paste (safe default). Lives in the App target: it touches AppKit/AX.
import AppKit
import ApplicationServices
import Core

public protocol PasteAvailabilityProbing: Sendable {
    func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool?
}

public struct PasteAvailabilityProbe: PasteAvailabilityProbing {
    public init() {}

    @MainActor
    public func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
        // Rules answer definitively (assume/deny paste): no AX walk, no Accessibility dependency.
        if !PasteAvailability.needsProbe(policy: policy) {
            return PasteAvailability.effective(policy: policy, probe: nil)
        }
        // AX drives the probe; without it we cannot inspect the menu bar.
        guard PermissionManager.shared.isAccessibilityGranted,
              let app, app.isTerminated == false else { return nil }
        let pid = app.processIdentifier
        return PasteAvailability.effective(policy: policy, probe: await probePaste(pid: pid))
    }

    /// Serial executor for the blocking AX probe. AX lookups must never run on the cooperative
    /// thread pool: a hung AX call would pin one of those threads, so it is confined to its own
    /// dedicated queue instead.
    private static let axProbeQueue = DispatchQueue(label: "com.openclip.ax-probe", qos: .userInitiated)

    /// Gates probe launches so at most one blocking AX worker is ever in flight. While a probe is
    /// stalled on a hung AX call, further requests fail fast (return nil) instead of spawning more
    /// blocked workers; the slot is released once the stalled call eventually returns.
    private actor ProbeSlot {
        var occupied = false
        func acquire() -> Bool {
            guard !occupied else { return false }
            occupied = true
            return true
        }
        func release() {
            occupied = false
        }
    }
    private static let probeSlot = ProbeSlot()

    /// Runs the AX Edit ▸ Paste lookup off the main actor on the dedicated blocking executor,
    /// racing it against the deadline. The timeout is enforced independently of the AX call:
    /// it resumes with nil while the (still blocked) lookup keeps occupying the single slot.
    /// Captures only `pid` (Sendable) so the continuation closure has no non-Sendable state.
    private nonisolated func probePaste(pid: pid_t) async -> Bool? {
        guard await Self.probeSlot.acquire() else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            let resume = OnceResume<Bool?>()
            let timeout = TaskBox()

            timeout.set(Task {
                try? await Task.sleep(nanoseconds: UInt64(Constants.pasteProbeTimeout * 1_000_000_000))
                if resume.resume(continuation, with: nil) {
                    // Keep the slot held: the AX call may still be blocked on the executor queue,
                    // and no additional blocked worker may be spawned while it is occupied.
                }
            })

            Self.axProbeQueue.async {
                let enabled = Self.editPasteEnabled(pid: pid)
                if resume.resume(continuation, with: enabled) {
                    timeout.cancel()
                }
                Task.detached { await Self.probeSlot.release() }
            }
        }
    }

    private nonisolated static func editPasteEnabled(pid: pid_t) -> Bool? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let pasteItem = AXMenuNavigator.findMenuItem(.paste, in: appElement, requireEnabled: false) else {
            return nil
        }
        return enabledState(of: pasteItem)
    }

    /// Is the exposed menu item a Paste command? Deferred to the shared menu navigator so copy/paste
    /// matching stays consistent with the retrieval path.
    nonisolated static func isPaste(title: String?, cmdChar: String?, cmdCharModifiers: UInt?) -> Bool {
        AXMenuNavigator.matches(.paste, title: title, identifier: nil, cmdChar: cmdChar, cmdModifiers: cmdCharModifiers)
    }

    private nonisolated static func enabledState(of element: AXUIElement) -> Bool? {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
              let value = enabledRef as? Bool else { return nil }
        return value
    }
}
