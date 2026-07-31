import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct ServicesAction: Action {
    public let id = "builtin.services"
    public let title = "Services"
    public let icon = ActionIcon.symbol("gearshape.2")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        #if canImport(AppKit)
        let text = context.selection.text
        if text.isEmpty { return .success }
        
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow ?? NSApp.windows.first, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        #endif
        return .success
    }
}
