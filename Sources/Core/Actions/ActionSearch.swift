// ActionSearch.swift
// OpenClip
//
// Defines the popup display mode and the pure, AppKit-free action-search matcher used by the
// popup's action-search palette. Matching is case-insensitive substring ranking: title prefix
// beats title contains, which beats keyword contains; ties keep original order.
import Foundation

/// The popup's display mode. Search mode is a UI state, never an Action in the registry.
public enum PopupMode: Sendable, Equatable {
    case actions
    case search
}

/// One searchable catalog entry. `title` is the display title, `keywords` adds searchable text
/// (package name, id) that does not show in results.
public struct ActionSearchIndex: Sendable {
    public let id: String
    public let title: String
    public let keywords: String
    public let action: any Action

    public init(id: String, title: String, keywords: String, action: any Action) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.action = action
    }
}

public enum ActionSearch {
    /// Returns `items` ranked by match quality for `query`, stable for equal scores.
    public static func search(_ query: String, in items: [ActionSearchIndex]) -> [ActionSearchIndex] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let normalized = trimmed.lowercased()

        let scored: [(offset: Int, item: ActionSearchIndex, score: Int)] = items.enumerated().compactMap { offset, item in
            let title = item.title.lowercased()
            let score: Int
            if title.hasPrefix(normalized) {
                score = 2
            } else if title.contains(normalized) {
                score = 1
            } else if item.keywords.lowercased().contains(normalized) {
                score = 0
            } else {
                return nil
            }
            return (offset, item, score)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.offset < rhs.offset
            }
            .map(\.item)
    }
}
