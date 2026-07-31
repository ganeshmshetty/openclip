import Foundation

public struct AppPolicyContext: Sendable {
    public let denyFormatting: Bool
    public let denyProbe: Bool
    public let denyPreprobe: Bool
    public let grabPasteboard: Bool
    public let grabKeyboard: Bool
    public let browserAddressBar: Bool
    public let assumePaste: Bool
    public let lenientSelect: Bool

    public static let `default` = AppPolicyContext(
        denyFormatting: false,
        denyProbe: false,
        denyPreprobe: false,
        grabPasteboard: false,
        grabKeyboard: false,
        browserAddressBar: false,
        assumePaste: false,
        lenientSelect: false
    )
}

public struct AppRule: Codable, Sendable {
    public let bundleIdentifiers: [String]
    public let denyFormatting: Bool?
    public let denyProbe: Bool?
    public let denyPreprobe: Bool?
    public let grabPasteboard: Bool?
    public let grabKeyboard: Bool?
    public let browserAddressBar: Bool?
    public let assumePaste: Bool?
    public let lenientSelect: Bool?
    
    public init(
        bundleIdentifiers: [String],
        denyFormatting: Bool? = nil,
        denyProbe: Bool? = nil,
        denyPreprobe: Bool? = nil,
        grabPasteboard: Bool? = nil,
        grabKeyboard: Bool? = nil,
        browserAddressBar: Bool? = nil,
        assumePaste: Bool? = nil,
        lenientSelect: Bool? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.denyFormatting = denyFormatting
        self.denyProbe = denyProbe
        self.denyPreprobe = denyPreprobe
        self.grabPasteboard = grabPasteboard
        self.grabKeyboard = grabKeyboard
        self.browserAddressBar = browserAddressBar
        self.assumePaste = assumePaste
        self.lenientSelect = lenientSelect
    }
}
