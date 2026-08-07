// ActionSearch.swift
// OpenClip
//
// Defines the popup display mode and the pure, AppKit-free action-search matcher used by the
// popup's action-search palette. Matching is case-insensitive: title prefix beats title contains,
// which beats a fuzzy title subsequence, which beats keyword contains. Within a tier, tighter
// fuzzy alignments come first, then usage recency (most recent first), then original order.
import Foundation

/// The popup's display mode. Search and content modes are UI states, never Actions in the registry.
public enum PopupMode: Sendable, Equatable {
    case actions
    case search
    case content
}

/// One searchable catalog entry. `title` is the display title, `keywords` adds searchable text
/// (package name, id) that does not show in results.
public struct ActionSearchIndex: Sendable {
    public let id: String
    public let title: String
    public let keywords: String
    public let action: any Action
    /// Pre-normalized (lowercased) search fields so `ActionSearch.search` never lowercases per
    /// catalog item per call — the index is built once per palette entry, so the cost lands
    /// there instead of on the per-keystroke hot path.
    let normalizedTitle: String
    let normalizedKeywords: String
    /// MRU usage counter (higher = more recent); breaks ties below match quality. Zero = never
    /// used. Baked in at index build, constant for a palette session.
    public let usageRecency: Int

    public init(id: String, title: String, keywords: String, action: any Action, usageRecency: Int = 0) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.action = action
        self.normalizedTitle = title.lowercased()
        self.normalizedKeywords = keywords.lowercased()
        self.usageRecency = usageRecency
    }
}

public enum ActionSearch {
    /// Returns `items` ranked for `query`. Match-kind tiers are hard: title prefix (3) beats
    /// title contains (2), which beats a fuzzy title subsequence (1), which beats keyword
    /// contains (0). Within a tier: tighter fuzzy alignments first, then usage recency (most
    /// recent first), then original (bar) order as the final tie-break.
    public static func search(_ query: String, in items: [ActionSearchIndex]) -> [ActionSearchIndex] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let normalized = trimmed.lowercased()

        let ranked: [(offset: Int, item: ActionSearchIndex, tier: Int, fuzzyScore: Int)] = items.enumerated().compactMap { offset, item in
            let tier: Int
            let fuzzyScore: Int
            if item.normalizedTitle.hasPrefix(normalized) {
                tier = 3
                fuzzyScore = 0
            } else if item.normalizedTitle.contains(normalized) {
                tier = 2
                fuzzyScore = 0
            } else if let fuzzy = fuzzyMatchScore(query: normalized, in: item.normalizedTitle), fuzzy >= 0 {
                tier = 1
                fuzzyScore = fuzzy
            } else if item.normalizedKeywords.contains(normalized) {
                tier = 0
                fuzzyScore = 0
            } else {
                return nil
            }
            return (offset, item, tier, fuzzyScore)
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
                if lhs.fuzzyScore != rhs.fuzzyScore { return lhs.fuzzyScore > rhs.fuzzyScore }
                if lhs.item.usageRecency != rhs.item.usageRecency { return lhs.item.usageRecency > rhs.item.usageRecency }
                return lhs.offset < rhs.offset
            }
            .map(\.item)
    }

    /// fzf-style subsequence score: each matched char gets a base score plus a word-boundary
    /// bonus (after whitespace/start/delimiter) and a consecutive-run bonus; chars skipped
    /// between matches incur a start + extension penalty. Computed over the optimal alignment
    /// with a small DP (titles are ~15 chars). Higher = tighter / better-anchored match.
    private static func fuzzyMatchScore(query: String, in text: String) -> Int? {
        let q = Array(query.utf8)
        let t = Array(text.utf8)
        let m = q.count
        let n = t.count
        guard m > 0, m <= n else { return nil }

        let scoreMatch = 16
        let bonusBoundary = 8
        let bonusDelimiter = 7
        let bonusConsecutive = 4
        let gapStart = -3
        let gapExtension = -1
        let sentinel = Int.min / 2

        func boundaryBonus(at j: Int) -> Int {
            if j == 0 { return bonusBoundary }
            let c = t[j - 1]
            if c == 32 { return bonusBoundary }                 // " "
            if c == 45 || c == 95 || c == 46 || c == 47 { return bonusDelimiter } // - _ . /
            return 0
        }

        var prev = [Int](repeating: sentinel, count: n)
        var curr = [Int](repeating: sentinel, count: n)

        for j in 0..<n where q[0] == t[j] {
            prev[j] = (scoreMatch + boundaryBonus(at: j)) * 2    // first-char multiplier
        }

        for i in 1..<m {
            var prefixMax = sentinel   // max over k<j of (prev[k] + k*gapExtension)
            for j in i..<n {
                prefixMax = max(prefixMax, prev[j - 1] + (j - 1) * gapExtension)
                guard q[i] == t[j] else { continue }
                let consecutive = prev[j - 1] + bonusConsecutive
                let gapped = prefixMax - gapStart - (j - 2) * gapExtension
                curr[j] = scoreMatch + boundaryBonus(at: j) + max(consecutive, gapped)
            }
            swap(&prev, &curr)
            curr = [Int](repeating: sentinel, count: n)
        }

        let best = prev.max() ?? sentinel
        return best <= sentinel / 2 ? nil : best
    }
}
