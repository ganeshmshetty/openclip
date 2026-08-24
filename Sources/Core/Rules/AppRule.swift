// AppRule.swift
// OpenClip
//
// Defines application-specific policy rules and match conditions for controlling OpenClip behavior per target application.
import Foundation

public struct AppPolicyContext: Sendable {
    /// Disables OpenClip entirely for the matching application (no popup, hotkeys ignored).
    public let disabled: Bool
    /// Suppresses the automatic popup on text selection; OpenClip will only trigger via explicit hotkey.
    public let hotkeyOnly: Bool
    /// Force a text result to be delivered as a copy instead of a paste, even when the app lists a
    /// Paste command. The explicit escape hatch for apps (e.g. Terminal) that advertise Paste but
    /// cannot reliably replace a selection.
    public let denyPaste: Bool
    /// Apps opting into menu-based copy read selected text via the AX Edit ▸ Copy menu item.
    public let useMenuCopy: Bool
    /// Which mechanism should be used to read the current selection from the target app.
    public let retrievalMode: SelectionRetrievalMode
    /// Gate rules (skip roles / allowed cursors / selection requirement) applied before retrieval.
    public let gate: SelectionGatePolicy

    public static let `default` = AppPolicyContext()

    public init(
        disabled: Bool = false,
        hotkeyOnly: Bool = false,
        denyPaste: Bool = false,
        useMenuCopy: Bool = false,
        retrievalMode: SelectionRetrievalMode = .axTextControl,
        gate: SelectionGatePolicy = .default
    ) {
        self.disabled = disabled
        self.hotkeyOnly = hotkeyOnly
        self.denyPaste = denyPaste
        self.useMenuCopy = useMenuCopy
        self.retrievalMode = retrievalMode
        self.gate = gate
    }
}

public struct AppRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleIdentifiers.first ?? UUID().uuidString }
    public let bundleIdentifiers: [String]
    public let disabled: Bool?
    public let hotkeyOnly: Bool?
    public let useMenuCopy: Bool?
    public let denyPaste: Bool?
    public let retrievalMode: SelectionRetrievalMode?
    public let gate: SelectionGatePolicy?
    
    public init(
        bundleIdentifiers: [String],
        disabled: Bool? = nil,
        hotkeyOnly: Bool? = nil,
        useMenuCopy: Bool? = nil,
        denyPaste: Bool? = nil,
        retrievalMode: SelectionRetrievalMode? = nil,
        gate: SelectionGatePolicy? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.disabled = disabled
        self.hotkeyOnly = hotkeyOnly
        self.useMenuCopy = useMenuCopy
        self.denyPaste = denyPaste
        self.retrievalMode = retrievalMode
        self.gate = gate
    }
    
    public enum CodingKeys: String, CodingKey {
        case bundleIdentifiers = "bundle-identifiers"
        case disabled = "disabled"
        case hotkeyOnly = "hotkey-only"
        case useMenuCopy = "use-menu-copy"
        case denyPaste = "deny-paste"
        case retrievalMode = "retrieval-mode"
        case gate = "gate"
    }
}
