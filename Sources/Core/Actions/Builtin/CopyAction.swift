// CopyAction.swift
// OpenClip
//
// Implements the standard copy action that returns a clipboard copy result for selected text.
//
// Delivery: no `delivery` declared (default nil). A secondary click copies (a copy primary is its
// own secondary), and the resolver's default toast already says "Copied" — nothing to add.
import Foundation

public struct CopyAction: ConfigurableAction {
    public let id = "builtin.copy"
    public var title: String { String(localized: "Copy") }
    public let preferenceIconName = "doc.on.doc"
    public var icon: ActionIcon { .text(String(localized: "Copy")) }
    
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, requiresLiveSelection: true)
    }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        if context.selection.html != nil || context.selection.rtf != nil {
            return .copyContent(RichPasteboardPayload(
                plainText: context.selection.text,
                rtf: context.selection.rtf,
                html: context.selection.html
            ))
        }
        return .copy(context.selection.text)
    }
}

