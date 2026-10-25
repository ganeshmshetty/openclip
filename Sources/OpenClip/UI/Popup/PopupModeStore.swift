// PopupModeStore.swift
// OpenClip
//
// Shared observable popup mode state: the screen mode, the result card payload and the pending
// additional-instruction request. Toasts bypass this store. The static preview uses a throwaway
// store so it never affects the live popup.
import Foundation
import Combine
import Core

@MainActor
public final class PopupModeStore: ObservableObject {
    /// Current screen: action bar, search palette, or result card.
    @Published public var mode: PopupMode = .actions
    /// The current search scope, if the palette is opened into a group's sub-actions.
    @Published public var scope: SearchScope? = nil
    /// True when the popup sits low on screen and search results render above the field.
    @Published public var searchResultsAbove: Bool = false
    /// True when the group sub-bar opens above the main bar; false when below.
    @Published public var subBarAbove: Bool = true
    /// Result card shown while `mode == .content`; any text outcome renders here.
    @Published public var resultCard: ResultCardPayload? = nil
    /// Max result-card size: the remembered user size, updated live during resize. `nil` means default.
    @Published public var resultCardSize: CGSize? = nil
    /// True once the user drags a resize handle; the card then keeps that size for its session.
    @Published public var isSurfaceUserSized: Bool = false
    /// Whether the target app can Paste (probed via AX). `false` hides Paste and Cut; `nil` and `true` keep them.
    @Published public var canPaste: Bool? = nil
    /// True while an async AI action runs; suspends distance auto-dismiss.
    @Published public var isProcessingAI: Bool = false
    /// True once the user pins the result card; suppresses auto-dismiss. Cleared by `hide()` and `exitContent()`.
    @Published public var isCardPinned: Bool = false
    /// True while the group sub-bar is visible; `PopupWindowController` uses it to intercept Escape.
    @Published public var isSubBarActive: Bool = false
    /// Active group action whose sub-bar is visible.
    @Published public var activeSubGroupID: String? = nil
    /// Inline results for `chrome.isInlineResult` actions, keyed by action ID.
    @Published public var inlineResults: [String: String] = [:]
    /// The AI preset waiting for its one-time additional instruction (only meaningful while
    /// `mode == .instruction`). Cleared when the instruction is submitted or the prompt cancelled.
    @Published public var instructionRequest: AdditionalInstructionRequest? = nil

    public init() {}
}

/// Payload for the native result card. `original` is the input text, kept for the character diff;
/// nil when there is nothing to compare.
public struct ResultCardPayload: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let title: String
    public let icon: ActionIcon?
    public let isStreaming: Bool
    public let original: String?
    /// Follow-up in flight with no chunk yet: `text` is the previous answer, shown dimmed.
    public let isRefining: Bool
    /// True for AI results that support follow-up refinement.
    public let canFollowUp: Bool
    public let file: FileOutputPayload?
    /// Position among the session's results (1-based) and how many exist, for the undo/redo switcher.
    public let versionIndex: Int
    public let versionCount: Int

    /// Builds the card content, including an optional native file.
    public init(text: String, isError: Bool, title: String = String(localized: "AI Tools"), icon: ActionIcon? = nil, isStreaming: Bool = false, original: String? = nil, isRefining: Bool = false, canFollowUp: Bool = true, file: FileOutputPayload? = nil, versionIndex: Int = 1, versionCount: Int = 1) {
        self.text = text
        self.isError = isError
        self.title = title
        self.icon = icon
        self.isStreaming = isStreaming
        self.original = original
        self.isRefining = isRefining
        self.canFollowUp = canFollowUp
        self.file = file
        self.versionIndex = versionIndex
        self.versionCount = versionCount
    }
}

/// One pending run of an AI preset that asks for an additional instruction: the preset as it was
/// when the action was triggered (its saved prompt is resolved, never rewritten) and the icon its
/// bar row shows. `id` distinguishes repeated requests for the same preset, so a submit can only
/// ever run the request it was typed into.
public struct AdditionalInstructionRequest: Equatable, Sendable {
    public let id: UUID
    public let preset: AIActionPreset
    public let icon: ActionIcon?

    public init(id: UUID = UUID(), preset: AIActionPreset, icon: ActionIcon? = nil) {
        self.id = id
        self.preset = preset
        self.icon = icon
    }
}

/// Scoped palette: a parent action and its pre-resolved children.
public struct SearchScope {
    public let parent: any Action
    public let children: [any Action]

    public init(parent: any Action, children: [any Action]) {
        self.parent = parent
        self.children = children
    }
}
