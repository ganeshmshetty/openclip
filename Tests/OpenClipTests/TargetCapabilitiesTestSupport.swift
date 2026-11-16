// TargetCapabilitiesTestSupport.swift
// OpenClipTests
//
// Compact capability fixtures for delivery tests: available unless a case says otherwise.
import Core

extension TargetCapabilities {
    static func stub(
        textInsertion: CapabilityAvailability = .available,
        pasteboardPaste: CapabilityAvailability = .available,
        targetIsLive: CapabilityAvailability = .available
    ) -> TargetCapabilities {
        TargetCapabilities(
            textInsertion: textInsertion,
            pasteboardPaste: pasteboardPaste,
            targetIsLive: targetIsLive
        )
    }

    /// A confirmed non-inserting target: read-only text, and no confirmed paste command.
    static var stubUnavailable: TargetCapabilities {
        .stub(textInsertion: .unavailable, pasteboardPaste: .unavailable)
    }
}
