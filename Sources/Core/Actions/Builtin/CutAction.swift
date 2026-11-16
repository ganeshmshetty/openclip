// CutAction.swift
// OpenClip
//
// Implements the standard cut action that returns a clipboard cut result for selected text.
//
// Delivery: no `delivery` declared (default nil). A secondary click keeps the cut primary (no
// derived copy for a cut), and there is no declared toast — matching the default behavior.
import Foundation

public struct CutAction: ConfigurableAction {
    public let id = "builtin.cut"
    public var title: String { String(localized: "Cut") }
    public let preferenceIconName = "scissors"
    public var icon: ActionIcon { .text(String(localized: "Cut")) }
    
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, requiresLiveSelection: true)
    }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        // Cut deletes the selection, so it needs positive proof the control accepts edits. The
        // paste destination is irrelevant; paste availability is a different capability.
        ActionEligibility.isSatisfied(
            [.text, .editableText],
            selection: context.selection,
            capabilities: context.capabilities,
            unknownSatisfies: false
        )
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .cut(context.selection.text)
    }
}
