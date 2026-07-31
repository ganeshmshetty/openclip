import Foundation
import CoreGraphics

public struct SelectionContext: Sendable {
    public let text: String
    public let sourceApp: any AppIdentifying
    public let cursorPosition: CGPoint
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    
    public init(text: String, sourceApp: any AppIdentifying, cursorPosition: CGPoint, timestamp: Date, appPolicy: AppPolicyContext) {
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.timestamp = timestamp
        self.appPolicy = appPolicy
    }
}
