// PopupModeStore.swift
// OpenClip
//
// Shared observable mode state for the popup: the screen mode (actions bar / search palette /
// content canvas) and the payloads those screens render (canvas content, hover preview strip,
// status banner). The real popup observes the store injected by PopupWindowController; the static
// preview uses a throwaway store so it never affects the live popup (mirrors the PopupHoverState
// shared + opt-in-static pattern).
import Foundation
import Combine
import Core

@MainActor
public final class PopupModeStore: ObservableObject {
    /// The popup's current mode: the normal action bar, the action-search palette, or the content canvas.
    @Published public var mode: PopupMode = .actions
    /// The current search scope, if the palette is opened into a group's sub-actions.
    @Published public var scope: SearchScope? = nil
    /// True when the popup sits low on screen and search results render above the field.
    @Published public var searchResultsAbove: Bool = false
    /// The content canvas currently shown (only meaningful while `mode == .content`).
    @Published public var content: PopupContent? = nil
    /// The hover preview strip shown while `mode == .actions` (bar stays visible, panel grows).
    @Published public var preview: PopupContent? = nil
    /// A transient inline status banner (auto-dismissed by the controller).
    @Published public var statusBanner: StatusFeedback? = nil

    public init() {}
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
