import AppKit

struct SelectionContext: Sendable {
    let text: String
    let sourceApp: NSRunningApplication
    let cursorPosition: CGPoint
    let timestamp: Date
}
