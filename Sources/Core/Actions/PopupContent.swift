// PopupContent.swift
// OpenClip
//
// Defines the value-type data model for the popup content canvas (PopupContentView): a single
// content shape that powers hover preview strips, result cards with delivery options, and
// vertical option menus. Pure Core value types — no AppKit/SwiftUI imports. The App target
// renders these via PopupContentView.
import Foundation

public enum ContentEmphasis: Sendable, Equatable {
    /// Small, dim hover preview strip (replaces OS `.help()` tooltips).
    case info
    /// Standard result card with a text body and delivery buttons (e.g. AI result, Calculate).
    case result
    /// Vertical sub-action list (e.g. transform options, paste-vs-copy choice).
    case menu
}

public enum ContentOutcome: Sendable {
    /// Deliver an execution result (handled by ActionResultHandler).
    case perform(ActionResult)
    /// Async outcome for menu sub-actions (extension group rows): executed by the popup after the
    /// menu option is clicked. `ActionContext` and `Action` are both Sendable, so the closure can
    /// capture them.
    case run(@Sendable () async throws -> ActionResult)
    /// Reserved: a nested content canvas launched from this option (not implemented in v1).
    case showSubMenu
}

public struct ContentOption: Sendable {
    public var title: String
    public var subtitle: String?
    public var icon: String?
    public var outcome: ContentOutcome

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        outcome: ContentOutcome
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.outcome = outcome
    }
}

public enum ContentRow: Sendable {
    case text(String)
    case option(ContentOption)
}

public struct PopupContent: Sendable {
    public var title: String?
    public var icon: String?
    public var subtitle: String?
    public var rows: [ContentRow]
    public var footer: [ContentOption]
    public var emphasis: ContentEmphasis

    public init(
        title: String? = nil,
        icon: String? = nil,
        subtitle: String? = nil,
        rows: [ContentRow] = [],
        footer: [ContentOption] = [],
        emphasis: ContentEmphasis = .result
    ) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.rows = rows
        self.footer = footer
        self.emphasis = emphasis
    }
}
