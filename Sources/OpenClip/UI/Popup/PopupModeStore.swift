// PopupModeStore.swift
// OpenClip
//
// Shared observable mode state for the popup: the screen mode (actions bar / search palette /
// native result card) and the payloads those screens render (result card payload). Statuses
// render as a floating toast via ToastPanelController, not through the store. The real popup
// observes the store injected by PopupWindowController; the static
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
    /// True when the group sub-bar opens above the main bar (indicator triangle sits at the top pointing up).
    /// False when it opens below the main bar (indicator triangle sits at the bottom pointing down).
    @Published public var subBarAbove: Bool = true
    /// The native result card currently shown (only meaningful while `mode == .content`). Any
    /// action whose resolved outcome is text renders here, not just AI presets.
    @Published public var resultCard: ResultCardPayload? = nil
    /// Whether the target app can Paste, probed (AX) when the popup shows. `false` hides the
    /// card's Paste button and the bar/search Paste + Cut actions; `nil` (unknown/probing) and
    /// `true` keep them visible.
    @Published public var canPaste: Bool? = nil
    /// True while an asynchronous AI action is executing, used to suspend distance auto-dismiss.
    @Published public var isProcessingAI: Bool = false
    /// True while the horizontal group sub-bar is visible (transient or pinned). Read by
    /// `PopupWindowController` to intercept Escape before dismissing the full popup.
    @Published public var isSubBarActive: Bool = false
    /// The ID of the currently active group action whose sub-bar is visible.
    @Published public var activeSubGroupID: String? = nil

    public init() {}
}

/// The payload of the native result card: the action's response text, whether it is an
/// error message (drives the card's styling), the producing action's title and icon, and
/// streaming state. `icon` is nil for AI streaming deliveries, which fall back to the
/// card's sparkles glyph.
public struct ResultCardPayload: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let title: String
    public let icon: ActionIcon?
    public let isStreaming: Bool

    public init(text: String, isError: Bool, title: String = String(localized: "AI Tools"), icon: ActionIcon? = nil, isStreaming: Bool = false) {
        self.text = text
        self.isError = isError
        self.title = title
        self.icon = icon
        self.isStreaming = isStreaming
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
