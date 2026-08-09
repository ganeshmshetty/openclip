// ResultContentProviding.swift
// OpenClip
//
// Defines the opt-in protocols that let an action feed the popup content canvas:
// a cheap hover preview line, and a full result card with delivery options. Only actions that
// conform are ever hover-previewed or show a long-press result card — safe for scripts and
// AI providers.
import Foundation

/// Provides a cheap, one-line preview of the action's outcome for the hover preview strip.
public protocol PreviewProviding: Action {
    @MainActor
    func previewLine(for context: ActionContext) async -> String?
}

/// Provides a full result tree (title chrome + body + delivery options) shown on long-press.
public protocol ResultContentProviding: Action {
    @MainActor
    func makeContent(for context: ActionContext) async -> CanvasComponent?
}
