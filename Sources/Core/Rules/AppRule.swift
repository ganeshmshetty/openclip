// AppRule.swift
// OpenClip
//
// Defines application-specific policy rules and match conditions for controlling OpenClip behavior per target application.
import Foundation

public struct AppPolicyContext: Sendable {
    public let denyFormatting: Bool
    public let denyProbe: Bool
    public let denyPreprobe: Bool
    public let assumePaste: Bool
    public let useMenuCopy: Bool
    /// Force a text result to be delivered as a copy instead of a paste, even when the app lists a
    /// Paste command. The explicit escape hatch for apps (e.g. Terminal) that advertise Paste but
    /// cannot reliably replace a selection.
    public let denyPaste: Bool

    public static let `default` = AppPolicyContext(
        denyFormatting: false,
        denyProbe: false,
        denyPreprobe: false,
        assumePaste: false,
        useMenuCopy: false,
        denyPaste: false
    )

    public init(
        denyFormatting: Bool = false,
        denyProbe: Bool = false,
        denyPreprobe: Bool = false,
        assumePaste: Bool = false,
        useMenuCopy: Bool = false,
        denyPaste: Bool = false
    ) {
        self.denyFormatting = denyFormatting
        self.denyProbe = denyProbe
        self.denyPreprobe = denyPreprobe
        self.assumePaste = assumePaste
        self.useMenuCopy = useMenuCopy
        self.denyPaste = denyPaste
    }
}

public struct AppRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleIdentifiers.first ?? UUID().uuidString }
    public let bundleIdentifiers: [String]
    public let denyFormatting: Bool?
    public let denyProbe: Bool?
    public let denyPreprobe: Bool?
    public let assumePaste: Bool?
    public let useMenuCopy: Bool?
    public let denyPaste: Bool?
    
    public init(
        bundleIdentifiers: [String],
        denyFormatting: Bool? = nil,
        denyProbe: Bool? = nil,
        denyPreprobe: Bool? = nil,
        assumePaste: Bool? = nil,
        useMenuCopy: Bool? = nil,
        denyPaste: Bool? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.denyFormatting = denyFormatting
        self.denyProbe = denyProbe
        self.denyPreprobe = denyPreprobe
        self.assumePaste = assumePaste
        self.useMenuCopy = useMenuCopy
        self.denyPaste = denyPaste
    }
    
    public enum CodingKeys: String, CodingKey {
        case bundleIdentifiers = "bundle-identifiers"
        case denyFormatting = "deny-formatting"
        case denyProbe = "deny-probe"
        case denyPreprobe = "deny-preprobe"
        case assumePaste = "assume-paste"
        case useMenuCopy = "use-menu-copy"
        case denyPaste = "deny-paste"
    }
}
