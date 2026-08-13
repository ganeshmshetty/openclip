// AppRule.swift
// OpenClip
//
// Defines application-specific policy rules and match conditions for controlling OpenClip behavior per target application.
import Foundation

public struct AppPolicyContext: Sendable {
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
        denyPaste: Bool = false,
        useMenuCopy: Bool = false,
        retrievalMode: SelectionRetrievalMode = .axTextControl,
        gate: SelectionGatePolicy = .default
    ) {
        self.denyPaste = denyPaste
        self.useMenuCopy = useMenuCopy
        self.retrievalMode = retrievalMode
        self.gate = gate
    }
}

public struct AppRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleIdentifiers.first ?? UUID().uuidString }
    public let bundleIdentifiers: [String]
    public let useMenuCopy: Bool?
    public let denyPaste: Bool?
    public let retrievalMode: SelectionRetrievalMode?
    public let gate: SelectionGatePolicy?
    
    public init(
        bundleIdentifiers: [String],
        useMenuCopy: Bool? = nil,
        denyPaste: Bool? = nil,
        retrievalMode: SelectionRetrievalMode? = nil,
        gate: SelectionGatePolicy? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.useMenuCopy = useMenuCopy
        self.denyPaste = denyPaste
        self.retrievalMode = retrievalMode
        self.gate = gate
    }
    
    public enum CodingKeys: String, CodingKey {
        case bundleIdentifiers = "bundle-identifiers"
        case useMenuCopy = "use-menu-copy"
        case denyPaste = "deny-paste"
        case retrievalMode = "retrieval-mode"
        case gate = "gate"
    }
}
