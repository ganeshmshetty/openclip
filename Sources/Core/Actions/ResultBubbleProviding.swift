// ResultBubbleProviding.swift
// OpenClip
//
// Defines the opt-in protocols that let an action feed the reusable popup bubble (BubbleCard):
// a cheap hover preview line, and a full result bubble with delivery options. Only actions that
// conform are ever hover-previewed or show a long-press bubble — safe for scripts and AI providers.
import Foundation

/// Provides a cheap, one-line preview of the action's outcome for the hover info bubble.
public protocol PreviewProviding: Action {
    @MainActor
    func previewLine(for context: ActionContext) async -> String?
}

/// Provides a full result bubble (title, body text, delivery options) shown on long-press.
public protocol ResultBubbleProviding: Action {
    @MainActor
    func makeBubble(for context: ActionContext) async -> BubbleContent?
}
