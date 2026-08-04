// ActionContext.swift
// OpenClip
//
// Encapsulates the execution context passed to actions, combining selection details, keyboard
// modifier flags, and the match info the shared visibility evaluator produced. The popup builds
// the matched context (via ActionVisibility) right before invoking perform.
import Foundation

public struct ActionContext: Sendable {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    /// Populated by the popup/coordinator when invoking perform for extension actions; nil for
    /// builtins and for direct perform calls that didn't go through match plumbing.
    public let match: ActionMatchInfo?
    
    public init(
        selection: SelectionContext,
        modifiers: ModifierFlags = [],
        match: ActionMatchInfo? = nil
    ) {
        self.selection = selection
        self.modifiers = modifiers
        self.match = match
    }
}
