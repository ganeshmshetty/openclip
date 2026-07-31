import Foundation
#if canImport(AppKit)
import AppKit
#endif

public struct CopyAction: Action {
    public let id = "builtin.copy"
    public let title = "Copy"
    public let icon = ActionIcon.symbol("doc.on.doc")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(context.selection.text, forType: .string)
        #endif
        return .copy(context.selection.text)
    }
}
