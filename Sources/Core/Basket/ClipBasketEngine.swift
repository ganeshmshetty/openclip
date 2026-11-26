// ClipBasketEngine.swift
// OpenClip
//
// Pure, value-semantic state machine for the Clip Basket. Every queue, split, reorder, undo and
// join rule lives here so the App target only renders and performs side effects.
import Foundation

public struct ClipBasketEngine: Sendable, Equatable {
    public private(set) var items: [ClipBasketItem]
    private var undoStack: [ClipBasketUndoEntry]
    public private(set) var order: ClipBasketOrder
    public private(set) var pasteAsPlainText: Bool
    public private(set) var joinFormat: ClipBasketJoinFormat
    public private(set) var isOpen: Bool
    public private(set) var isCommandVArmed: Bool

    public init(
        items: [ClipBasketItem] = [],
        order: ClipBasketOrder = .fifo,
        pasteAsPlainText: Bool = false,
        joinFormat: ClipBasketJoinFormat = .newline,
        isOpen: Bool = false,
        isCommandVArmed: Bool = false
    ) {
        self.items = items
        self.undoStack = []
        self.order = order
        self.pasteAsPlainText = pasteAsPlainText
        self.joinFormat = joinFormat
        self.isOpen = isOpen
        self.isCommandVArmed = isCommandVArmed
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var nextItem: ClipBasketItem? { items.first }

    public mutating func enqueue(_ item: ClipBasketItem) {
        if order == .fifo {
            items.append(item)
        } else {
            items.insert(item, at: 0)
        }
    }

    /// Splits a multi-line selection into one item per non-empty line.
    @discardableResult
    public mutating func enqueueSplit(
        _ text: String,
        sourceApp: AppIdentity? = nil,
        separator: CharacterSet = .newlines
    ) -> Int {
        let lines = text
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines {
            enqueue(ClipBasketItem(
                content: .text(RichPasteboardPayload(plainText: line)),
                sourceApp: sourceApp
            ))
        }
        return lines.count
    }

    @discardableResult
    public mutating func popNext() -> ClipBasketItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        undoStack.append(.popped(item: item, index: 0))
        return item
    }

    @discardableResult
    public mutating func pop(id: UUID) -> ClipBasketItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        undoStack.append(.removed(item: item, index: index))
        return item
    }

    @discardableResult
    public mutating func undo() -> ClipBasketItem? {
        guard let entry = undoStack.popLast() else { return nil }
        let index = min(max(entry.index, 0), items.count)
        items.insert(entry.item, at: index)
        return entry.item
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { items.indices.contains($0) }.sorted()
        guard !valid.isEmpty else { return }
        let moving = valid.map { items[$0] }
        let removedBefore = valid.filter { $0 < destination }.count
        for index in valid.reversed() {
            items.remove(at: index)
        }
        let insertion = min(max(destination - removedBefore, 0), items.count)
        items.insert(contentsOf: moving, at: insertion)
    }

    /// Moves a single row to the index it should occupy after the move.
    public mutating func move(id: UUID, toIndex destination: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(destination, 0), items.count - 1)
        guard source != target else { return }
        move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
    }

    public mutating func reverse() {
        order = order == .fifo ? .lifo : .fifo
        items.reverse()
    }

    public func joinedText(format: ClipBasketJoinFormat? = nil) -> String? {
        let parts = items.compactMap(\.content.plainText).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        switch format ?? joinFormat {
        case .newline:
            return parts.joined(separator: "\n")
        case .doubleNewline:
            return parts.joined(separator: "\n\n")
        case .space:
            return parts.joined(separator: " ")
        case .comma:
            return parts.joined(separator: ", ")
        case .bulletList:
            return parts.map { "• \($0)" }.joined(separator: "\n")
        case .numberedList:
            return parts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
    }

    public mutating func clear() {
        items.removeAll()
        undoStack.removeAll()
        isCommandVArmed = false
    }

    public mutating func setOrder(_ order: ClipBasketOrder) {
        self.order = order
    }

    public mutating func setPasteAsPlainText(_ value: Bool) {
        pasteAsPlainText = value
    }

    public mutating func setJoinFormat(_ format: ClipBasketJoinFormat) {
        joinFormat = format
    }

    public mutating func setOpen(_ value: Bool) {
        isOpen = value
        if !value { isCommandVArmed = false }
    }

    public mutating func setCommandVArmed(_ value: Bool) {
        isCommandVArmed = value && isOpen && !items.isEmpty
    }
}
