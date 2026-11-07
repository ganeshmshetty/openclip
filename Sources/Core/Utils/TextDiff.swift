// TextDiff.swift
// OpenClip
//
// Hierarchical diff between an action's input and its output, for the result card's change view.
// Returns equal/insert/delete segments; styling is left to the card.
//
// Tokenize (words, whitespace, single symbols), trim common prefix/suffix tokens, run Myers on the
// tokens so unrelated words aren't chopped, then refine single-word typos and case changes at
// character level ("hey" -> "Hey" highlights only "h"->"H"). Budgets (`maxComparableLength`,
// `maxEditDistance`) fall back to one whole-middle replacement.
import Foundation

/// One run of the diff: a stretch of text that survived, was added, or was removed.
public struct TextDiffSegment: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case equal
        case insert
        case delete
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public enum TextDiff {
    /// Budget for the trimmed middle; beyond it the middle is reported as one replacement.
    public static let maxComparableLength = 2_500
    /// Myers search budget; its cost grows with D², so unrelated texts must not run unbounded.
    public static let maxEditDistance = 300

    /// True when the two texts differ only in whitespace (line breaks, spaces, tabs), so a diff
    /// would only repaint the old line structure and add noise.
    public static func differsOnlyInWhitespace(from old: String, to new: String) -> Bool {
        guard old != new else { return false }
        return old.filter { !$0.isWhitespace } == new.filter { !$0.isWhitespace }
    }

    /// True for a revision (proofreading, tone, spelling) rather than a rewrite (translation, summary).
    public static func isMeaningfulEdit(from old: String, to new: String, minSimilarity: Double = 0.5) -> Bool {
        let trimmedOld = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty, trimmedOld != trimmedNew else { return false }
        guard !differsOnlyInWhitespace(from: trimmedOld, to: trimmedNew) else { return false }
        guard trimmedOld.count <= maxComparableLength, trimmedNew.count <= maxComparableLength else { return false }
        let segs = segments(from: trimmedOld, to: trimmedNew)
        guard segs.contains(where: { $0.kind != .equal }), segs.contains(where: { $0.kind == .equal }) else {
            return false
        }
        return equalRatio(of: segs) >= minSimilarity
    }

    /// Diffs `old` into `new` as coalesced equal/insert/delete segments.
    public static func segments(from old: String, to new: String) -> [TextDiffSegment] {
        if old == new {
            return old.isEmpty ? [] : [TextDiffSegment(kind: .equal, text: old)]
        }

        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        var prefixCount = 0
        while prefixCount < oldTokens.count,
              prefixCount < newTokens.count,
              oldTokens[prefixCount] == newTokens[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < oldTokens.count - prefixCount,
              suffixCount < newTokens.count - prefixCount,
              oldTokens[oldTokens.count - 1 - suffixCount] == newTokens[newTokens.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let oldMiddleTokens = Array(oldTokens[prefixCount..<(oldTokens.count - suffixCount)])
        let newMiddleTokens = Array(newTokens[prefixCount..<(newTokens.count - suffixCount)])

        let oldMiddleText = oldMiddleTokens.joined()
        let newMiddleText = newMiddleTokens.joined()

        let middle: [TextDiffSegment]
        if oldMiddleText.count + newMiddleText.count > maxComparableLength {
            middle = replacement(oldMiddleText, newMiddleText)
        } else if let tokenOps = myers(oldMiddleTokens, newMiddleTokens, maxDistance: maxEditDistance) {
            var middleSegs: [TextDiffSegment] = []
            var pendingDeleted: [String] = []
            var pendingInserted: [String] = []
            var pendingWhitespaceEquals: [String] = []

            func flushPending() {
                if !pendingDeleted.isEmpty || !pendingInserted.isEmpty {
                    middleSegs.append(contentsOf: resolveCluster(deleted: pendingDeleted, inserted: pendingInserted))
                    pendingDeleted.removeAll()
                    pendingInserted.removeAll()
                }
                if !pendingWhitespaceEquals.isEmpty {
                    for ws in pendingWhitespaceEquals {
                        middleSegs.append(TextDiffSegment(kind: .equal, text: ws))
                    }
                    pendingWhitespaceEquals.removeAll()
                }
            }

            for op in tokenOps {
                switch op {
                case .equal(let token):
                    if isWhitespaceToken(token) && (!pendingDeleted.isEmpty || !pendingInserted.isEmpty) {
                        // Whitespace after an edit may join the same edit cluster.
                        pendingWhitespaceEquals.append(token)
                    } else {
                        // Stable anchor: flush pending edits.
                        flushPending()
                        middleSegs.append(TextDiffSegment(kind: .equal, text: token))
                    }
                case .delete(let token):
                    if !pendingWhitespaceEquals.isEmpty {
                        // Edit continues across whitespace: absorb the whitespace into the cluster
                        pendingDeleted.append(contentsOf: pendingWhitespaceEquals)
                        pendingInserted.append(contentsOf: pendingWhitespaceEquals)
                        pendingWhitespaceEquals.removeAll()
                    }
                    pendingDeleted.append(token)
                case .insert(let token):
                    if !pendingWhitespaceEquals.isEmpty {
                        pendingDeleted.append(contentsOf: pendingWhitespaceEquals)
                        pendingInserted.append(contentsOf: pendingWhitespaceEquals)
                        pendingWhitespaceEquals.removeAll()
                    }
                    pendingInserted.append(token)
                }
            }
            flushPending()
            middle = middleSegs
        } else {
            middle = replacement(oldMiddleText, newMiddleText)
        }

        var result: [TextDiffSegment] = []
        if prefixCount > 0 {
            result.append(TextDiffSegment(kind: .equal, text: oldTokens[0..<prefixCount].joined()))
        }
        result.append(contentsOf: middle)
        if suffixCount > 0 {
            result.append(TextDiffSegment(kind: .equal, text: oldTokens[(oldTokens.count - suffixCount)...].joined()))
        }
        return coalesced(result)
    }

    /// Share of the material that survived unchanged: 1.0 when identical, near 0 for a rewrite.
    public static func equalRatio(of segments: [TextDiffSegment]) -> Double {
        var equal = 0
        var total = 0
        for segment in segments {
            let count = segment.text.count
            total += count
            if segment.kind == .equal { equal += count }
        }
        guard total > 0 else { return 1.0 }
        return Double(equal) / Double(total)
    }

    // MARK: - Internals

    /// Partitions text into word runs, whitespace runs, and single punctuation/symbols.
    /// Guarantee: `tokenize(text).joined() == text`.
    public static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var currentToken = ""
        var currentCategory: TokenCategory?

        enum TokenCategory {
            case word
            case whitespace
            case other
        }

        for char in text {
            let category: TokenCategory
            if char.isLetter || char.isNumber {
                category = .word
            } else if char.isWhitespace || char.isNewline {
                category = .whitespace
            } else {
                category = .other
            }

            if let current = currentCategory {
                if category == current && category != .other {
                    currentToken.append(char)
                } else {
                    tokens.append(currentToken)
                    currentToken = String(char)
                    currentCategory = category
                }
            } else {
                currentToken = String(char)
                currentCategory = category
            }
        }
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        return tokens
    }

    private static func isWord(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isLetter || first.isNumber
    }

    private static func isWhitespaceToken(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return first.isWhitespace || first.isNewline
    }

    private static func replacement(_ old: String, _ new: String) -> [TextDiffSegment] {
        var segments: [TextDiffSegment] = []
        if !old.isEmpty { segments.append(TextDiffSegment(kind: .delete, text: old)) }
        if !new.isEmpty { segments.append(TextDiffSegment(kind: .insert, text: new)) }
        return segments
    }

    private static func resolveCluster(deleted: [String], inserted: [String]) -> [TextDiffSegment] {
        let dText = deleted.joined()
        let iText = inserted.joined()

        guard !dText.isEmpty || !iText.isEmpty else { return [] }
        guard !dText.isEmpty else { return [TextDiffSegment(kind: .insert, text: iText)] }
        guard !iText.isEmpty else { return [TextDiffSegment(kind: .delete, text: dText)] }

        let dAlpha = dText.filter { $0.isLetter || $0.isNumber }.lowercased()
        let iAlpha = iText.filter { $0.isLetter || $0.isNumber }.lowercased()

        let isCaseOrPunctuationOnly = !dAlpha.isEmpty && dAlpha == iAlpha
        let chars1 = Array(dText)
        let chars2 = Array(iText)

        if let refinedOps = myers(chars1, chars2, maxDistance: maxEditDistance) {
            if isCaseOrPunctuationOnly || shouldRefineCluster(count1: chars1.count, count2: chars2.count, charOps: refinedOps) {
                return segmentsFromCharOps(refinedOps)
            }
        }

        var segments: [TextDiffSegment] = []
        segments.append(TextDiffSegment(kind: .delete, text: dText))
        segments.append(TextDiffSegment(kind: .insert, text: iText))
        return segments
    }

    private static func shouldRefineCluster(count1: Int, count2: Int, charOps: [DiffOp<Character>]) -> Bool {
        guard count1 >= 3 || count2 >= 3 else { return false }

        var equalChars = 0
        for op in charOps {
            if case .equal = op {
                equalChars += 1
            }
        }

        guard equalChars >= 3 else { return false }
        let maxLen = max(count1, count2)
        return Double(equalChars) / Double(maxLen) >= 0.60
    }

    private static func segmentsFromCharOps(_ ops: [DiffOp<Character>]) -> [TextDiffSegment] {
        var segments: [TextDiffSegment] = []
        var currentKind: TextDiffSegment.Kind?
        var currentText = ""

        for op in ops {
            let kind: TextDiffSegment.Kind
            let char: Character
            switch op {
            case .equal(let c):
                kind = .equal
                char = c
            case .insert(let c):
                kind = .insert
                char = c
            case .delete(let c):
                kind = .delete
                char = c
            }

            if kind == currentKind {
                currentText.append(char)
            } else {
                if let currentKind, !currentText.isEmpty {
                    segments.append(TextDiffSegment(kind: currentKind, text: currentText))
                }
                currentKind = kind
                currentText = String(char)
            }
        }
        if let currentKind, !currentText.isEmpty {
            segments.append(TextDiffSegment(kind: currentKind, text: currentText))
        }
        return segments
    }

    private enum DiffOp<Element> {
        case equal(Element)
        case insert(Element)
        case delete(Element)
    }

    /// Myers greedy diff with a D budget, generic over any Equatable sequence elements.
    private static func myers<T: Equatable>(_ a: [T], _ b: [T], maxDistance: Int) -> [DiffOp<T>]? {
        let n = a.count
        let m = b.count
        if n == 0 && m == 0 { return [] }
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }

        let bound = min(n + m, maxDistance)
        let offset = bound + 1
        var v = [Int](repeating: 0, count: 2 * bound + 3)
        var trace: [[Int]] = []
        trace.reserveCapacity(bound + 1)

        for d in 0...bound {
            trace.append(v)
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n && y >= m {
                    return backtrack(a, b, trace: trace, offset: offset)
                }
                k += 2
            }
        }
        return nil
    }

    private static func backtrack<T: Equatable>(_ a: [T], _ b: [T], trace: [[Int]], offset: Int) -> [DiffOp<T>] {
        var x = a.count
        var y = b.count
        var reversed: [DiffOp<T>] = []

        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let v = trace[d]
            let k = x - y
            let previousK: Int
            if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = v[offset + previousK]
            let previousY = previousX - previousK

            while x > previousX && y > previousY {
                x -= 1
                y -= 1
                reversed.append(.equal(a[x]))
            }
            guard d > 0 else { break }
            if x == previousX {
                y -= 1
                reversed.append(.insert(b[y]))
            } else {
                x -= 1
                reversed.append(.delete(a[x]))
            }
        }
        return reversed.reversed()
    }

    /// Merges neighbouring segments of the same kind (the prefix/suffix joints produce them).
    private static func coalesced(_ segments: [TextDiffSegment]) -> [TextDiffSegment] {
        var merged: [TextDiffSegment] = []
        for segment in segments where !segment.text.isEmpty {
            if let last = merged.last, last.kind == segment.kind {
                merged[merged.count - 1] = TextDiffSegment(kind: last.kind, text: last.text + segment.text)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}
