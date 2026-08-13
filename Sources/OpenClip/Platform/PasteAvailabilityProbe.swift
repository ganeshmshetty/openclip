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
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef, CFGetTypeID(menuBarRef) == AXUIElementGetTypeID(),
              let childrenRef = copyChildren(menuBarRef as! AXUIElement) else { return nil }

        // The Paste item is found by its Command-V key equivalent (localization-independent) or by
        // a localization-aware title match, so non-English menus (e.g. "Édition ▸ Coller") probe
        // correctly instead of always falling back to copy. Scanning every top-level menu covers
        // the Edit menu without relying on its localized title.
        for item in childrenRef {
            let menuChildren = copyChildren(item) ?? []
            let menu = menuChildren.first ?? item
            let menuItems = copyChildren(menu) ?? []
            for pasteCandidate in menuItems {
                guard isPasteItem(pasteCandidate) else { continue }
                return enabledState(of: pasteCandidate)
            }
        }
        return nil
    }

    private nonisolated static func isPasteItem(_ element: AXUIElement) -> Bool {
        isPaste(title: copyTitle(element), cmdChar: copyCmdChar(element), cmdCharModifiers: copyCmdModifiers(element))
    }

    /// Is the exposed menu item a Paste command? Primary signal: a Command-V key equivalent.
    /// Fallback: a title in `pasteMenuTitles`, a curated localization-aware set (English included)
    /// for apps that don't publish a key equivalent.
    nonisolated static func isPaste(title: String?, cmdChar: String?, cmdCharModifiers: UInt?) -> Bool {
        if let cmdChar, cmdChar == "V",
           let modifiers = cmdCharModifiers {
            return modifiers & UInt(AXMenuItemModifiers.noCommand.rawValue) == 0
        }
        guard let title else { return false }
        return pasteMenuTitles.contains(title.localizedLowercase)
    }

    /// Curated "Paste" menu titles across the most common system localizations, used only when the
    /// menu item exposes no Command-V equivalent.
    static let pasteMenuTitles: Set<String> = [
        "paste", "paste and match style",      // en
        "coller", "coller et assortir le style", // fr
        "einfügen", "einfügen und stil anpassen", // de
        "pegar", "pegar y combinar estilo",    // es
        "incolla",                             // it
        "colar", "colar e combinar estilo",    // pt
        "plakken", "plakken en stijl aanpassen", // nl
        "klistra",                             // sv
        "indsæt",                              // da
        "lim inn",                             // no
        "liitä",                               // fi
        "wklej",                               // pl
        "vložit",                              // cs
        "вставить",                            // ru
        "粘贴", "貼上",                        // zh-Hans / zh-Hant
        "붙여넣기",                            // ko
        "貼り付け", "ペースト",                // ja
        "beillesztés",                          // hu
        "yapıştır",                             // tr
        "επικόλληση",                           // el
    ]

    private nonisolated static func enabledState(of element: AXUIElement) -> Bool? {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success,
              let value = enabledRef as? Bool else { return nil }
        return value
    }

    private nonisolated static func copyTitle(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String else { return nil }
        return title
    }

    private nonisolated static func copyCmdChar(_ element: AXUIElement) -> String? {
        var charRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdCharAttribute as CFString, &charRef) == .success,
              let char = charRef as? String else { return nil }
        return char
    }

    private nonisolated static func copyCmdModifiers(_ element: AXUIElement) -> UInt? {
        var modifiersRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuItemCmdModifiersAttribute as CFString, &modifiersRef) == .success,
              let modifiers = modifiersRef as? NSNumber else { return nil }
        return modifiers.uintValue
    }

    private nonisolated static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        return children
    }
}
