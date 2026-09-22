// DecisionQuestion.swift
// OpenClip
//
// Typed decision questions (noul / choice / score) that Decision tools ask of a selection.
// Inspired by TypeSafe System One / Laya schemas — pure Core, no AppKit/SwiftUI.
import Foundation

/// Kind of judgment a Decision tool requests.
public enum DecisionQuestionKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// Yes / no (noul = null/boolean polarity).
    case noul
    /// Pick one (or more) from a closed list.
    case choice
    /// Ordinal score on an inclusive integer range.
    case score
}

/// A single typed question packed into a provider request.
public struct DecisionQuestion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: DecisionQuestionKind
    public var prompt: String
    /// Closed option labels for `.choice`. Ignored for other kinds.
    public var options: [String]
    /// Inclusive lower bound for `.score`.
    public var scoreMin: Int
    /// Inclusive upper bound for `.score`.
    public var scoreMax: Int
    /// When true, `.choice` may return multiple selected labels.
    public var allowsMultiple: Bool

    public init(
        id: String,
        kind: DecisionQuestionKind,
        prompt: String,
        options: [String] = [],
        scoreMin: Int = 1,
        scoreMax: Int = 5,
        allowsMultiple: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.options = options
        self.scoreMin = scoreMin
        self.scoreMax = scoreMax
        self.allowsMultiple = allowsMultiple
    }

    public static func noul(id: String, prompt: String) -> DecisionQuestion {
        DecisionQuestion(id: id, kind: .noul, prompt: prompt)
    }

    public static func choice(id: String, prompt: String, options: [String], allowsMultiple: Bool = false) -> DecisionQuestion {
        DecisionQuestion(id: id, kind: .choice, prompt: prompt, options: options, allowsMultiple: allowsMultiple)
    }

    public static func score(id: String, prompt: String, min: Int = 1, max: Int = 5) -> DecisionQuestion {
        DecisionQuestion(id: id, kind: .score, prompt: prompt, scoreMin: min, scoreMax: max)
    }
}

/// Request body packed for System One / Laya-compatible providers.
public struct DecisionRequest: Codable, Sendable, Equatable {
    /// Opaque state / selection context the model judges (never rewritten).
    public var state: String
    public var questions: [DecisionQuestion]
    /// Optional tool id for logging / fixtures.
    public var toolID: String?

    public init(state: String, questions: [DecisionQuestion], toolID: String? = nil) {
        self.state = state
        self.questions = questions
        self.toolID = toolID
    }
}

/// Packs questions + selection into the wire JSON shape providers expect.
public enum DecisionQuestionPacker {
    /// Encode a request as JSON Data (UTF-8).
    public static func encodeRequest(_ request: DecisionRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(WireRequest(from: request))
    }

    /// Build a request from a tool's primary question and optional follow-ups.
    public static func pack(
        state: String,
        questions: [DecisionQuestion],
        toolID: String? = nil
    ) -> DecisionRequest {
        DecisionRequest(
            state: state.trimmingCharacters(in: .whitespacesAndNewlines),
            questions: questions,
            toolID: toolID
        )
    }

    /// Wire DTO matching TypeSafe System One / Laya conventions.
    struct WireRequest: Codable, Sendable {
        var state: String
        var questions: [WireQuestion]
        var tool_id: String?

        init(from request: DecisionRequest) {
            state = request.state
            tool_id = request.toolID
            questions = request.questions.map { q in
                WireQuestion(
                    id: q.id,
                    type: q.kind.rawValue,
                    prompt: q.prompt,
                    options: q.kind == .choice ? q.options : nil,
                    min: q.kind == .score ? q.scoreMin : nil,
                    max: q.kind == .score ? q.scoreMax : nil,
                    multiple: q.kind == .choice ? q.allowsMultiple : nil
                )
            }
        }
    }

    struct WireQuestion: Codable, Sendable {
        var id: String
        var type: String
        var prompt: String
        var options: [String]?
        var min: Int?
        var max: Int?
        var multiple: Bool?
    }
}
