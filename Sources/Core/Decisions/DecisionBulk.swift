// DecisionBulk.swift
// OpenClip
//
// Bulk Decision map/reduce: split selection into units, judge each, reduce to filtered paste / marks.
import Foundation

public enum DecisionBulkUnitKind: String, Codable, Sendable, Equatable, CaseIterable {
    case line
    case row
    case word
    case span
    case paragraph
}

public struct DecisionBulkUnit: Sendable, Equatable, Identifiable {
    public var id: Int
    public var text: String
    public var range: Range<String.Index>?

    public init(id: Int, text: String, range: Range<String.Index>? = nil) {
        self.id = id
        self.text = text
        self.range = range
    }
}

public struct DecisionBulkLimits: Sendable, Equatable {
    public var maxUnits: Int
    /// Wall-clock budget in seconds for the whole batch.
    public var budgetSeconds: TimeInterval

    public static let `default` = DecisionBulkLimits(maxUnits: 100, budgetSeconds: 8)

    public init(maxUnits: Int = 100, budgetSeconds: TimeInterval = 8) {
        self.maxUnits = max(1, maxUnits)
        self.budgetSeconds = max(0.1, budgetSeconds)
    }
}

public struct DecisionBulkJudgment: Sendable, Equatable {
    public var unitID: Int
    public var keep: Bool
    public var mark: String?
    public var confidence: Double?

    public init(unitID: Int, keep: Bool, mark: String? = nil, confidence: Double? = nil) {
        self.unitID = unitID
        self.keep = keep
        self.mark = mark
        self.confidence = confidence
    }
}

public enum DecisionBulkReducer {
    /// Split text into units of the requested kind, capped at `limits.maxUnits`.
    public static func split(
        _ text: String,
        kind: DecisionBulkUnitKind,
        limits: DecisionBulkLimits = .default
    ) -> [DecisionBulkUnit] {
        let trimmed = text
        guard !trimmed.isEmpty else { return [] }
        let parts: [String]
        switch kind {
        case .line, .row:
            parts = trimmed.components(separatedBy: .newlines)
        case .paragraph:
            parts = trimmed.components(separatedBy: "\n\n").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        case .word:
            parts = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
        case .span:
            // Approximate spans: sentences ending with .!? or newlines.
            parts = splitSpans(trimmed)
        }
        return Array(parts.prefix(limits.maxUnits).enumerated().map { DecisionBulkUnit(id: $0.offset, text: $0.element) })
    }

    private static func splitSpans(_ text: String) -> [String] {
        var spans: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?\n".contains(ch) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { spans.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { spans.append(tail) }
        return spans
    }

    /// Reduce judgments to a filtered paste string and optional mark annotations.
    public static func reduce(
        units: [DecisionBulkUnit],
        judgments: [DecisionBulkJudgment],
        joinSeparator: String = "\n"
    ) -> (paste: String, marks: [String]) {
        let byID = Dictionary(uniqueKeysWithValues: judgments.map { ($0.unitID, $0) })
        var kept: [String] = []
        var marks: [String] = []
        for unit in units {
            guard let j = byID[unit.id] else { continue }
            if j.keep {
                kept.append(unit.text)
            }
            if let mark = j.mark, !mark.isEmpty {
                marks.append("[\(unit.id)] \(mark): \(unit.text)")
            }
        }
        return (kept.joined(separator: joinSeparator), marks)
    }

    /// Whether another unit may run given elapsed time and budget.
    public static func withinBudget(elapsed: TimeInterval, limits: DecisionBulkLimits) -> Bool {
        elapsed < limits.budgetSeconds
    }
}
