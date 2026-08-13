// PopupModeStore.swift
// OpenClip
//
// Shared observable mode state for the popup: the screen mode (actions bar / search palette /
// native AI result card) and the payloads those screens render (AI result payload, status
// banner). The real popup observes the store injected by PopupWindowController; the static
// preview uses a throwaway store so it never affects the live popup (mirrors the PopupHoverState
// shared + opt-in-static pattern).
import Foundation
import Combine
import Core

@MainActor
public final class PopupModeStore: ObservableObject {
    /// The popup's current mode: the normal action bar, the action-search palette, or the
    /// native AI result card.
    @Published public var mode: PopupMode = .actions
    /// The current search scope, if the palette is opened into a group's sub-actions.
    @Published public var scope: SearchScope? = nil
    /// True when the popup sits low on screen and search results render above the field.
    @Published public var searchResultsAbove: Bool = false
    /// The native AI result card currently shown (only meaningful while `mode == .content`).
    @Published public var aiResult: AIResultPayload? = nil
    /// Whether the target app can Paste, probed (AX) when the popup shows. `false` hides the
    /// card's Paste button and the bar/search Paste + Cut actions; `nil` (unknown/probing) and
    /// `true` keep them visible.
    @Published public var canPaste: Bool? = nil
    /// A transient inline status banner (auto-dismissed by the controller).
    @Published public var statusBanner: StatusFeedback? = nil

    public init() {}
}

/// The payload of the native AI result card: the provider's response text, whether it is an
/// error message (drives the card's styling), and the producing preset's title.
public struct AIResultPayload: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let title: String

    public init(text: String, isError: Bool, title: String = "AI Tools") {
        self.text = text
        self.isError = isError
        self.title = title
    }
}

/// A scoped palette: a parent action (the group row / the AI launcher) and its pre-resolved children.
public struct SearchScope {
    public let parent: any Action
    public let children: [any Action]

    public init(parent: any Action, children: [any Action]) {
        self.parent = parent
        self.children = children
    }
}
