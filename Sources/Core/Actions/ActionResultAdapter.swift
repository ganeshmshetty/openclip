// ActionResultAdapter.swift
// OpenClip
//
// The single declarative `after`/`stayVisible` translator (plan §6, decision 7). Runtimes return
// only raw runtime results; the factory's attached `rules` (after/stayVisible) are applied here
// ONCE at the end of each runtime's perform. `copyResult`/`pasteResult` override leaf copy/paste,
// `none` collapses any result to success, runtime presentations always pass through untouched,
// `stayVisible` wraps in `.keepVisible` only when the normalized result would otherwise dismiss,
// and `showResult` degrades to the plain leaf result (canvas card rendering was removed). Pure
// Core — no AppKit/SwiftUI.
import Foundation

public enum ActionResultAdapter {
    public static func apply(
        raw: ActionResult,
        after: ActionAfterBehavior,
        stayVisible: Bool
    ) -> ActionResult {
        let normalized: ActionResult
        switch (after, raw) {
        case (.copyResult, .paste(let s)), (.copyResult, .copy(let s)):
            normalized = .copy(s)
        case (.pasteResult, .copy(let s)), (.pasteResult, .paste(let s)):
            normalized = .paste(s)
        case (_, .showStatus), (_, .openConfiguration),
             (_, .keyPress), (_, .runShortcut), (_, .keepVisible), (_, .sequence):
            // Runtime presentations always win — pass through unchanged.
            normalized = raw
        case (.none, _):
            normalized = .success
        default:
            // Includes `.showResult` — with canvas rendering removed it degrades to the plain
            // leaf result (copy/paste) instead of wrapping it in a result card.
            normalized = raw
        }
        if stayVisible, normalized.dismissesPopup {
            return .keepVisible(normalized)
        }
        return normalized
    }
}

public extension ActionIcon {
    /// The SF Symbol name for symbol icons; nil for local/url/text icons.
    var symbolName: String? {
        switch self {
        case .symbol(let name): return name
        case .local, .url, .text: return nil
        }
    }
}
