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
    /// True when the action was triggered by a secondary click (right-click or ⇧-click). Populated
    /// by the popup at perform time from the captured click intent; lets an action change its
    /// behavior (e.g. Define returns the definition as a copy instead of opening the app).
    public let isSecondaryClick: Bool
    /// Populated by the popup/coordinator when invoking perform for extension actions; nil for
    /// builtins and for direct perform calls that didn't go through match plumbing.
    public let match: ActionMatchInfo?
    /// Paste destination evidence captured for this popup session; nil is unknown and only fails
    /// actions that explicitly require a paste destination.
    public let pasteTargetAvailable: Bool?
    /// Presentation-scoped cache shared by the bar, palette, and prewarm for this picker session.
    public let visibilityMemo: VisibilityMemo

    public init(
        selection: SelectionContext,
        modifiers: ModifierFlags = [],
        isSecondaryClick: Bool = false,
        match: ActionMatchInfo? = nil,
        pasteTargetAvailable: Bool? = nil,
        visibilityMemo: VisibilityMemo? = nil
    ) {
        self.selection = selection
        self.modifiers = modifiers
        self.isSecondaryClick = isSecondaryClick
        self.match = match
        self.pasteTargetAvailable = pasteTargetAvailable ?? selection.pasteTargetAvailable
        self.visibilityMemo = visibilityMemo ?? VisibilityMemo()
    }
}
