// ClipBasketEngine.swift
// OpenClip
//
// Pure, value-semantic state machine for the Clip Basket. Every queue, split, reorder, undo and
// join rule lives here so the App target only renders and performs side effects.
import Foundation

public struct ClipBasketEngine: Sendable, Equatable {
    public static let defaultMaximumItems = 100
    public static let defaultMaximumTotalBytes = 200 * 1024 * 1024

    public private(set) var items: [ClipBasketItem]
    private var undoStack: [ClipBasketUndoEntry]
    public private(set) var order: ClipBasketOrder
    public private(set) var pasteAsPlainText: Bool
    public private(set) var joinFormat: ClipBasketJoinFormat
    public private(set) var isOpen: Bool
    public private(set) var isCommandVArmed: Bool
    public let maximumItems: Int
    public let maximumTotalBytes: Int

    public init(
        items: [ClipBasketItem] = [],
        order: ClipBasketOrder = .fifo,
        pasteAsPlainText: Bool = false,
        joinFormat: ClipBasketJoinFormat = .newline,
        isOpen: Bool = false,
        isCommandVArmed: Bool = false,
        maximumItems: Int = ClipBasketEngine.defaultMaximumItems,
        maximumTotalBytes: Int = ClipBasketEngine.defaultMaximumTotalBytes
    ) {
        self.items = items
        self.undoStack = []
        self.order = order
        self.pasteAsPlainText = pasteAsPlainText
        self.joinFormat = joinFormat
        self.isOpen = isOpen
        self.isCommandVArmed = isCommandVArmed
        self.maximumItems = maximumItems
        self.maximumTotalBytes = maximumTotalBytes
    }

    public var count: Int { items.count }
    public var isEmpty: Bool { items.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var nextItem: ClipBasketItem? { items.first }
    public var estimatedBytes: Int { items.reduce(0) { $0 + $1.estimatedByteCount } }
    public var isFull: Bool {
        items.count >= maximumItems || estimatedBytes >= maximumTotalBytes
    }

    @discardableResult
    public mutating func enqueue(_ item: ClipBasketItem) -> Bool {
        guard items.count < maximumItems,
              estimatedBytes + item.estimatedByteCount <= maximumTotalBytes else {
            return false
        }
        if order == .fifo {
            items.append(item)
        } else {
            items.insert(item, at: 0)
        }
        return true
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
        var added = 0
        for line in lines {
            let didAdd = enqueue(ClipBasketItem(
                content: .text(RichPasteboardPayload(plainText: line)),
                sourceApp: sourceApp
            ))
            guard didAdd else { break }
            added += 1
        }
        return added
    }

    @discardableResult
    public mutating func popNext() -> ClipBasketItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeFirst()
        undoStack.append(.popped(item: item, index: 0))
        if items.isEmpty { isCommandVArmed = false }
        return item
    }

    @discardableResult
    public mutating func pop(id: UUID) -> ClipBasketItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        undoStack.append(.removed(item: item, index: index))
        if items.isEmpty { isCommandVArmed = false }
        return item
    }

    @discardableResult
    public mutating func undo() -> ClipBasketItem? {
        guard let entry = undoStack.popLast() else { return nil }
        let index = min(max(entry.index, 0), items.count)
        guard !items.contains(where: { $0.id == entry.item.id }) else { return entry.item }
        items.insert(entry.item, at: index)
        return entry.item
    }

    /// Puts a delivery rollback back at its original position without adding an undo entry.
    public mutating func restore(_ item: ClipBasketItem, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        undoStack.removeAll { $0.item.id == item.id }
        let insertion = min(max(index, 0), items.count)
        items.insert(item, at: insertion)
    }

    public mutating func remove(ids: [UUID]) {
        for id in ids {
            _ = pop(id: id)
        }
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
        joinedTextSnapshot(format: format)?.text
    }

    /// The join used by delivery, plus the exact text items included so Paste All can remove only
    /// what it pasted.
    public func joinedTextSnapshot(format: ClipBasketJoinFormat? = nil) -> (text: String, itemIDs: [UUID])? {
        let textItems = items.filter { item in
            item.content.isText && !((item.content.plainText) ?? "").isEmpty
        }
        let parts = textItems.compactMap(\.content.plainText)
        guard !parts.isEmpty else { return nil }
        return (Self.join(parts, format: format ?? joinFormat), textItems.map(\.id))
    }

    private static func join(_ parts: [String], format: ClipBasketJoinFormat) -> String {
        switch format {
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
