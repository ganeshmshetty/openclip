// PopupGesturePolicy.swift
// OpenClip
//
// Defines the data-driven gesture policy for the popup bar, derived from an action's chrome
// metadata and protocol conformance. The UI reads this value and executes it — it never decides
// interaction behavior itself. This is a UI-only presentation concern, so it lives in the App
// target (not `Core`); the derived policy is consumed solely by the popup views and the hover
// support in this folder.
import Foundation
import Core

public struct PopupGesturePolicy: Sendable, Equatable {
    public enum SingleClick: Sendable, Equatable {
        /// Run the action immediately (fast path).
        case perform
        /// Open the sub-action palette scoped to this group.
        case openSubActions
    }

    public let singleClick: SingleClick

    public init(singleClick: SingleClick) {
        self.singleClick = singleClick
    }
}

public extension Action {
    /// Derives the popup interaction policy from chrome metadata.
    /// No UI type checks, no string matching.
    @MainActor
    var gesturePolicy: PopupGesturePolicy {
        switch chrome.popupBehavior {
        case .showSubActions:
            return PopupGesturePolicy(singleClick: .openSubActions)
        case .provideCompletions, .perform:
            return PopupGesturePolicy(singleClick: .perform)
        }
    }
}
