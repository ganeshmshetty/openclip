import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif

public struct PasteAction: Action {
    public let id = "builtin.paste"
    public let title = "Paste"
    public let icon = ActionIcon.symbol("doc.on.clipboard")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        #if canImport(AppKit)
        let hasString = NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        return context.isEditable && hasString
        #else
        return context.isEditable
        #endif
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        #if canImport(AppKit)
        let pastedText = NSPasteboard.general.string(forType: .string) ?? ""
        
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            keydown.flags = .maskCommand
            keyup.flags = .maskCommand
            keydown.post(tap: .cghidEventTap)
            keyup.post(tap: .cghidEventTap)
        }
        return .paste(pastedText)
        #else
        return .paste("")
        #endif
    }
}
