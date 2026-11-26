// AddToBasketAction.swift
// OpenClip
//
// Collects the live selection into the ephemeral Clip Basket. Option-click splits a multi-line
// selection into one item per line for sequential form filling.
import Foundation

public struct AddToBasketAction: ConfigurableAction {
    public let id = "builtin.addToBasket"
    public var title: String { String(localized: "Add to Basket") }
    public let icon = ActionIcon.symbol("basket")
    public let preferenceIconName = "basket"

    private let store: ClipBasketStore

    @MainActor
    public init(store: ClipBasketStore = .shared) {
        self.store = store
    }

    public var chrome: ActionChrome {
        ActionChrome(
            badge: .none,
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .builtin,
            requiresLiveSelection: true
        )
    }

    public var keywords: [String] {
        [String(localized: "basket"), String(localized: "clip"), String(localized: "queue"), String(localized: "collect")]
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        !context.selection.isClipboardFallback && !context.selection.text.isEmpty
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let sourceApp = context.selection.sourceApp

        if context.modifiers.contains(.option) {
            let added = store.enqueueSplit(context.selection.text, sourceApp: sourceApp)
            guard added > 0 else {
                return .toast(StatusFeedback(
                    message: String(localized: "Nothing to Add"),
                    style: .info,
                    symbolName: "basket"
                ))
            }
            return .toast(StatusFeedback(
                message: String(format: String(localized: "Added %lld Items to Basket"), added),
                style: .success,
                symbolName: "basket"
            ))
        }

        store.enqueue(ClipBasketItem(content: .text(payload(for: context.selection)), sourceApp: sourceApp))
        return .toast(StatusFeedback(
            message: String(localized: "Added to Basket"),
            style: .success,
            symbolName: "basket"
        ))
    }

    private func payload(for selection: SelectionContext) -> RichPasteboardPayload {
        if selection.html != nil || selection.rtf != nil || !selection.flavors.isEmpty {
            return RichPasteboardPayload(
                plainText: selection.text,
                rtf: selection.rtf,
                html: selection.html,
                flavors: selection.flavors
            )
        }
        return RichPasteboardPayload(plainText: selection.text)
    }
}
