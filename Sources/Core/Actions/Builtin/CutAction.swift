// CutAction.swift
// OpenClip
//
// Implements the standard cut action that returns a clipboard cut result for selected text.
import Foundation

public struct CutAction: ConfigurableAction {
    public let id = "builtin.cut"
    public let title = "Cut"
    public let configurationViewID = "builtin.cut"
    public let preferenceIconName = "scissors"
    public let icon = ActionIcon.symbol("scissors")
    
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

