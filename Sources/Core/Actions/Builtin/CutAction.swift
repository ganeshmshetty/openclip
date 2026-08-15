// CutAction.swift
// OpenClip
//
// Implements the standard cut action that returns a clipboard cut result for selected text.
//
// Delivery: no `delivery` declared (default nil). A secondary click keeps the cut primary (no
// derived copy for a cut), and there is no declared toast — matching the default behavior.
import Foundation

public struct CutAction: ConfigurableAction, PasteRequiringAction {
    public let id = "builtin.cut"
    public let title = "Cut"
    public let preferenceIconName = "scissors"
    public let icon = ActionIcon.text("Cut")
    
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, requiresLiveSelection: true)
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

