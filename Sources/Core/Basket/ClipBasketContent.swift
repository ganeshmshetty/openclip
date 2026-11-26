// ClipBasketContent.swift
// OpenClip
//
// Pure value types for an ephemeral, task-scoped clip collection. Text reuses the existing
// rich pasteboard payload so a basket item keeps its formatting until paste time.
import Foundation

public enum ClipBasketContent: Sendable, Equatable {
    case text(RichPasteboardPayload)
    case image(data: Data, uti: String, pixelWidth: Int?, pixelHeight: Int?)
    case files([URL])

    /// Plain text for joining and row previews; nil for media items.
    public var plainText: String? {
        if case .text(let payload) = self {
            return payload.plainText
        }
        return nil
    }

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

public struct ClipBasketItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let content: ClipBasketContent
    public let sourceApp: AppIdentity?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        content: ClipBasketContent,
        sourceApp: AppIdentity? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.sourceApp = sourceApp
        self.createdAt = createdAt
    }
}

public enum ClipBasketOrder: String, Codable, CaseIterable, Sendable {
    /// Queue: first collected, first pasted. Best for forms.
    case fifo
    /// Stack: last collected, first pasted.
    case lifo
}

public enum ClipBasketJoinFormat: String, Codable, CaseIterable, Sendable {
    case newline
    case doubleNewline
    case space
    case comma
    case bulletList
    case numberedList
}

enum ClipBasketUndoEntry: Sendable, Equatable {
    case popped(item: ClipBasketItem, index: Int)
    case removed(item: ClipBasketItem, index: Int)

    var item: ClipBasketItem {
        switch self {
        case .popped(let item, _), .removed(let item, _):
            return item
        }
    }

    var index: Int {
        switch self {
        case .popped(_, let index), .removed(_, let index):
            return index
        }
    }
}
