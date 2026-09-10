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
    /// The most room the result card may take — the user's remembered size, restored from
    /// preferences (`SettingKey.resultCardWidth` / `resultCardHeight`) when content mode is
    /// entered and updated live while a resize handle is dragged. The card renders at what its
    /// text needs up to this; `nil` means the default maximum. Cleared whenever the card leaves
    /// the screen, so every entry re-reads the preference.
    @Published public var resultCardSize: CGSize? = nil
    /// The most room the search palette may take — the user's remembered size, restored from
    /// preferences (`SettingKey.searchPaletteWidth` / `searchPaletteHeight`) when search mode is
    /// entered and updated live while a resize handle is dragged. The palette renders at what its
    /// results need up to this; `nil` means the default column. Cleared whenever the palette
    /// closes, so every entry re-reads the preference.
    @Published public var searchPaletteSize: CGSize? = nil
    /// True once the user has dragged a resize handle of the surface on screen. From then on the
    /// surface keeps the dragged size verbatim — any size they want, whatever its content does —
    /// for the rest of its session. Cleared when the surface closes, so the next one opens
    /// content-fitted up to the remembered maximum.
    @Published public var isSurfaceUserSized: Bool = false
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
    /// Computed inline results for actions with `chrome.isInlineResult == true`, keyed by action ID.
    @Published public var inlineResults: [String: String] = [:]

    public init() {}
}

/// The payload of the native result card: the action's response text, whether it is an
/// error message (drives the card's styling), the producing action's title and icon, and
/// streaming state. `icon` is nil for AI streaming deliveries, which fall back to the
/// card's sparkles glyph. `original` is the text the action was run on (the selection), kept so
/// the card can show a character-level diff of what the action changed; nil when there is
/// nothing to compare against.
public struct ResultCardPayload: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let title: String
    public let icon: ActionIcon?
    public let isStreaming: Bool
    public let original: String?

    public init(text: String, isError: Bool, title: String = String(localized: "AI Tools"), icon: ActionIcon? = nil, isStreaming: Bool = false, original: String? = nil) {
        self.text = text
        self.isError = isError
        self.title = title
        self.icon = icon
        self.isStreaming = isStreaming
        self.original = original
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
