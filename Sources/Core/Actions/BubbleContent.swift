// BubbleContent.swift
// OpenClip
//
// Defines the value-type data model for the reusable popup bubble (BubbleCard): a single content
// shape that powers hover info tooltips, result previews with delivery options, and sub-action menus.
// Pure Core value types — no AppKit/SwiftUI imports. The App target renders these via BubbleCardView.
import Foundation

public enum BubbleEmphasis: Sendable, Equatable {
    /// Small, dim hover tooltip (replaces OS `.help()` tooltips).
    case info
    /// Standard result card with a text body and delivery buttons (e.g. AI overlay, Calculate).
    case result
    /// Vertical sub-action list (e.g. transform options, paste-vs-copy choice).
    case menu
}

public enum BubbleOutcome: Sendable {
    /// Deliver an execution result (handled by ActionResultHandler).
    case perform(ActionResult)
    /// Async outcome for menu sub-actions (extension group rows): executed by the popup after the
    /// menu option is clicked. `ActionContext` and `Action` are both Sendable, so the closure can
    /// capture them.
    case run(@Sendable () async throws -> ActionResult)
    /// Reserved: a nested bubble launched from this option (not implemented in v1).
    case showSubMenu
}

public struct BubbleOption: Sendable {
    public var title: String
    public var subtitle: String?
    public var icon: String?
    public var outcome: BubbleOutcome

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        outcome: BubbleOutcome
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.outcome = outcome
    }
}

public enum BubbleRow: Sendable {
    case text(String)
    case option(BubbleOption)
}

public struct BubbleContent: Sendable {
    public var title: String?
    public var icon: String?
    public var subtitle: String?
    public var rows: [BubbleRow]
    public var footer: [BubbleOption]
    public var emphasis: BubbleEmphasis

    public init(
        title: String? = nil,
        icon: String? = nil,
        subtitle: String? = nil,
        rows: [BubbleRow] = [],
        footer: [BubbleOption] = [],
        emphasis: BubbleEmphasis = .result
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.rows = rows
        self.footer = footer
        self.emphasis = emphasis
    }
}
