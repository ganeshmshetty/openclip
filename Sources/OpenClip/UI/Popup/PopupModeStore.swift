// PopupModeStore.swift
// OpenClip
//
// Shared observable mode state for the popup. The real popup observes the store injected by
// PopupWindowController; the static preview uses a throwaway store so it never affects the live
// popup (mirrors the PopupHoverState shared + opt-in-static pattern).
import Foundation
import Combine
import Core

@MainActor
public final class PopupModeStore: ObservableObject {
    /// The popup's current mode: the normal action bar or the action-search palette.
    @Published public var mode: PopupMode = .actions
    /// The current search scope, if the palette is opened into a group's sub-actions.
    @Published public var scope: SearchScope? = nil
    /// True when the popup sits low on screen and search results render above the field.
    @Published public var searchResultsAbove: Bool = false

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
