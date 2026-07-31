import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif

public struct CutAction: Action {
    public let id = "builtin.cut"
    public let title = "Cut"
    public let icon = ActionIcon.symbol("scissors")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return context.isEditable && !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(context.selection.text, forType: .string)
        
        let src = CGEventSource(stateID: .hidSystemState)
        let deleteKey: CGKeyCode = 0x33
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: deleteKey, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: deleteKey, keyDown: false) {
            keydown.post(tap: .cghidEventTap)
            keyup.post(tap: .cghidEventTap)
        }
        #endif
        return .copy(context.selection.text)
    }
}
