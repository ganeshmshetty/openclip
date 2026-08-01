import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct AirDropAction: Action {
    public let id = "builtin.airdrop"
    public let title = "AirDrop"
    public let icon = ActionIcon.symbol("airdrop")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        if text.isEmpty { return .success }
        return .airdrop(text)
    }
}
