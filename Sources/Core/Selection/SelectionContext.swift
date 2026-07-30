import Foundation
import CoreGraphics

public struct SelectionContext: Sendable {
    public let text: String
    public let sourceApp: any AppIdentifying
    public let cursorPosition: CGPoint
    public let timestamp: Date
    
    public init(text: String, sourceApp: any AppIdentifying, cursorPosition: CGPoint, timestamp: Date) {
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.timestamp = timestamp
    }
}
