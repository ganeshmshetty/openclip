// ActionResultAdapter.swift
// OpenClip
//
// The single declarative `after`/`stayVisible` translator (plan §6, decision 7). Runtimes return
// only raw runtime results; the factory's attached `rules` (after/stayVisible) are applied here
// ONCE at the end of each runtime's perform. `copyResult`/`pasteResult` override leaf copy/paste,
// `showResult` wraps a string outcome in a BubbleContent card, `none` collapses any result to
// success, runtime presentations always pass through untouched, and `stayVisible` wraps in
// `.keepVisible` only when the normalized result would otherwise dismiss. Pure Core — no
// AppKit/SwiftUI.
import Foundation

public enum ActionResultAdapter {
    public static func apply(
        raw: ActionResult,
        after: ActionAfterBehavior,
        stayVisible: Bool,
        title: String,
        icon: String?
    ) -> ActionResult {
        let normalized: ActionResult
        switch (after, raw) {
        case (.copyResult, .paste(let s)), (.copyResult, .copy(let s)):
            normalized = .copy(s)
        case (.pasteResult, .copy(let s)), (.pasteResult, .paste(let s)):
            normalized = .paste(s)
        case (_, .showBubble), (_, .showStatus), (_, .openConfiguration),
             (_, .keyPress), (_, .runShortcut), (_, .keepVisible), (_, .sequence):
            // Runtime presentations always win — pass through unchanged.
            normalized = raw
        case (.showResult, .copy(let s)), (.showResult, .paste(let s)):
            normalized = .showBubble(BubbleContent(
                title: title, icon: icon, rows: [.text(s)],
                footer: [
                    BubbleOption(title: "Paste", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste(s))),
                    BubbleOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy(s)))
                ],
                emphasis: .result
            ))
        case (.none, _):
            normalized = .success
        default:
            normalized = raw
        }
        if stayVisible, normalized.dismissesPopup {
            return .keepVisible(normalized)
        }
        return normalized
    }
}

public extension ActionIcon {
    /// The SF Symbol name for symbol icons; nil for local/url/text icons. Used to thread a runtime's
    /// icon into the adapter's `showResult` bubble.
    var symbolName: String? {
        switch self {
        case .symbol(let name): return name
        case .local, .url, .text: return nil
        }
    }
}
