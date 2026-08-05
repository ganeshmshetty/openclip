// PopupGesturePolicy.swift
// OpenClip
//
// Defines the data-driven gesture policy for the popup bar, derived from an action's chrome
// metadata and protocol conformance. The UI reads this value and executes it — it never decides
// interaction behavior itself. Keeps Core AppKit-free; conformance checks live here, not in views.
import Foundation

public struct PopupGesturePolicy: Sendable, Equatable {
    public enum SingleClick: Sendable, Equatable {
        /// Run the action immediately (fast path).
        case perform
        /// Open the sub-action palette scoped to this group.
        case openSubActions
        /// Show the result bubble directly instead of performing (opt-in actions).
        case showResultBubble
    }

    public let singleClick: SingleClick
    /// What a long-press does; nil means long-press is not handled (click proceeds normally).
    public let longPress: SingleClick?
    /// Whether hovering shows a cheap preview line in the info bubble.
    public let hoverPreview: Bool

    public init(
        singleClick: SingleClick,
        longPress: SingleClick? = nil,
        hoverPreview: Bool = false
    ) {
        self.singleClick = singleClick
        self.longPress = longPress
        self.hoverPreview = hoverPreview
    }
}

public extension Action {
    /// Derives the popup interaction policy from chrome metadata + protocol conformance.
    /// No UI type checks, no string matching.
    @MainActor
    var gesturePolicy: PopupGesturePolicy {
        switch chrome.popupBehavior {
        case .showTransformMenu:
            return PopupGesturePolicy(singleClick: .openSubActions)
        case .provideCompletions:
            return PopupGesturePolicy(singleClick: .perform)
        case .perform:
            if self is any ResultBubbleProviding {
                return PopupGesturePolicy(
                    singleClick: .perform,
                    longPress: .showResultBubble,
                    hoverPreview: self is any PreviewProviding
                )
            }
            return PopupGesturePolicy(
                singleClick: .perform,
                hoverPreview: self is any PreviewProviding
            )
        }
    }
}
