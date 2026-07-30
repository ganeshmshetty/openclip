import AppKit

struct SelectionContext: @unchecked Sendable {
    let text: String
    let sourceApp: NSRunningApplication
    let cursorPosition: CGPoint
    let timestamp: Date
}
