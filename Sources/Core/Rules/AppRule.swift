// AppRule.swift
// OpenClip
//
// Defines application-specific policy rules and match conditions for controlling OpenClip behavior per target application.
import Foundation

public struct AppPolicyContext: Sendable {
    public let denyFormatting: Bool
    public let denyProbe: Bool
    public let denyPreprobe: Bool
    public let grabPasteboard: Bool
    public let assumePaste: Bool

    public static let `default` = AppPolicyContext(
        denyFormatting: false,
        denyProbe: false,
        denyPreprobe: false,
        grabPasteboard: false,
        assumePaste: false
    )
}

public struct AppRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String { bundleIdentifiers.first ?? UUID().uuidString }
    public let bundleIdentifiers: [String]
    public let denyFormatting: Bool?
    public let denyProbe: Bool?
    public let denyPreprobe: Bool?
    public let grabPasteboard: Bool?
    public let assumePaste: Bool?
    
    public init(
        bundleIdentifiers: [String],
        denyFormatting: Bool? = nil,
        denyProbe: Bool? = nil,
        denyPreprobe: Bool? = nil,
        grabPasteboard: Bool? = nil,
        assumePaste: Bool? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.denyFormatting = denyFormatting
        self.denyProbe = denyProbe
        self.denyPreprobe = denyPreprobe
        self.grabPasteboard = grabPasteboard
        self.assumePaste = assumePaste
    }
    
    public enum CodingKeys: String, CodingKey {
        case bundleIdentifiers = "bundle-identifiers"
        case denyFormatting = "deny-formatting"
        case denyProbe = "deny-probe"
        case denyPreprobe = "deny-preprobe"
        case grabPasteboard = "grab-pb"
        case assumePaste = "assume-paste"
    }
}
