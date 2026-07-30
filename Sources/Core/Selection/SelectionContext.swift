// `import AppKit` is necessary here for macOS-specific core selection logic,
// such as interacting with NSRunningApplication, NSPasteboard, and Accessibility APIs.
import AppKit

struct SelectionContext: @unchecked Sendable {
    let text: String
    let sourceApp: NSRunningApplication
    let cursorPosition: CGPoint
    let timestamp: Date
}
