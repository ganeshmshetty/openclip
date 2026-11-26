// ClipBasketStore.swift
// OpenClip
//
// Main-actor observable wrapper around ClipBasketEngine. Persists the user's order, plain-text and
// join preferences through SettingsStore; item contents stay strictly in memory.
import Foundation
import Combine

@MainActor
public final class ClipBasketStore: ObservableObject {
    public static let shared = ClipBasketStore()

    @Published public private(set) var engine: ClipBasketEngine

    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        self.engine = ClipBasketEngine(
            order: ClipBasketOrder(rawValue: settingsStore.get(.clipBasketOrder)) ?? .fifo,
            pasteAsPlainText: settingsStore.get(.clipBasketPasteAsPlainText),
            joinFormat: ClipBasketJoinFormat(rawValue: settingsStore.get(.clipBasketJoinFormat)) ?? .newline
        )
    }

    public var items: [ClipBasketItem] { engine.items }
    public var count: Int { engine.count }
    public var isEmpty: Bool { engine.isEmpty }
    public var canUndo: Bool { engine.canUndo }
    public var nextItem: ClipBasketItem? { engine.nextItem }
    public var order: ClipBasketOrder { engine.order }
    public var pasteAsPlainText: Bool { engine.pasteAsPlainText }
    public var joinFormat: ClipBasketJoinFormat { engine.joinFormat }
    public var isOpen: Bool { engine.isOpen }
    public var isCommandVArmed: Bool { engine.isCommandVArmed }

    public var joinedText: String? { engine.joinedText() }

    public func enqueue(_ item: ClipBasketItem) {
        engine.enqueue(item)
        Log.basket.debug("enqueued kind=\(Self.kind(of: item), privacy: .public) count=\(self.engine.count, privacy: .public)")
    }

    @discardableResult
    public func enqueueSplit(_ text: String, sourceApp: AppIdentity?) -> Int {
        let added = engine.enqueueSplit(text, sourceApp: sourceApp)
        Log.basket.debug("split added=\(added, privacy: .public) count=\(self.engine.count, privacy: .public)")
        return added
    }

    @discardableResult
    public func popNext() -> ClipBasketItem? {
        let item = engine.popNext()
        if item != nil {
            Log.basket.debug("popped next count=\(self.engine.count, privacy: .public)")
        }
        return item
    }

    @discardableResult
    public func pop(id: UUID) -> ClipBasketItem? {
        let item = engine.pop(id: id)
        if item != nil {
            Log.basket.debug("removed item count=\(self.engine.count, privacy: .public)")
        }
        return item
    }

    @discardableResult
    public func undo() -> ClipBasketItem? {
        let item = engine.undo()
        if item != nil {
            Log.basket.debug("undid removal count=\(self.engine.count, privacy: .public)")
        }
        return item
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        engine.move(fromOffsets: source, toOffset: destination)
    }

    public func move(id: UUID, toIndex destination: Int) {
        engine.move(id: id, toIndex: destination)
    }

    public func reverse() {
        engine.reverse()
        settingsStore.set(.clipBasketOrder, value: engine.order.rawValue)
        Log.basket.debug("order=\(self.engine.order.rawValue, privacy: .public)")
    }

    public func setPasteAsPlainText(_ value: Bool) {
        engine.setPasteAsPlainText(value)
        settingsStore.set(.clipBasketPasteAsPlainText, value: value)
    }

    public func setJoinFormat(_ format: ClipBasketJoinFormat) {
        engine.setJoinFormat(format)
        settingsStore.set(.clipBasketJoinFormat, value: format.rawValue)
    }

    public func setOpen(_ value: Bool) {
        engine.setOpen(value)
    }

    public func setCommandVArmed(_ value: Bool) {
        engine.setCommandVArmed(value)
    }

    public func clear() {
        engine.clear()
        Log.basket.debug("cleared")
    }

    private static func kind(of item: ClipBasketItem) -> String {
        switch item.content {
        case .text: return "text"
        case .image: return "image"
        case .files: return "files"
        }
    }
}
