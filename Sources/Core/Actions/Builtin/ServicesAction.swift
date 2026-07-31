import Foundation
#if canImport(AppKit)
import AppKit
#endif

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
        return .success
    }
}
