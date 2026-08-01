import Foundation
import Core

public struct CutAction: Action {
    public let id = "builtin.cut"
    public let title = "Cut"
    public var icon: ActionIcon {
        if UserDefaults.standard.bool(forKey: "action.cut.useText") {
            return .text("Cut")
        }
        return .symbol("scissors")
    }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .cut(context.selection.text)
    }
}
