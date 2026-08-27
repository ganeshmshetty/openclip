import Foundation

public struct AXSelectionPayload: Codable, Sendable, Equatable {
    public let text: String?
    public let boundsX: Double?
    public let boundsY: Double?
    public let boundsWidth: Double?
    public let boundsHeight: Double?
    public let sourceBundleID: String?

    public init(
        text: String? = nil,
        boundsX: Double? = nil,
        boundsY: Double? = nil,
        boundsWidth: Double? = nil,
        boundsHeight: Double? = nil,
        sourceBundleID: String? = nil
    ) {
        self.text = text
        self.boundsX = boundsX
        self.boundsY = boundsY
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
        self.sourceBundleID = sourceBundleID
    }
}

public struct AXKeyCommandPayload: Codable, Sendable, Equatable {
    public let keyCode: UInt16
    public let flagsRaw: UInt64

    public init(keyCode: UInt16, flagsRaw: UInt64) {
        self.keyCode = keyCode
        self.flagsRaw = flagsRaw
    }
}
