// DecisionAnswer.swift
// OpenClip
//
// Typed answers returned by Decision providers — never free-form essays.
import Foundation

/// Value carried by a Decision answer.
public enum DecisionAnswerValue: Codable, Sendable, Equatable {
    case noul(Bool)
    case choice([String])
    case score(Int)

    public var displayLabel: String {
        switch self {
        case .noul(let yes): return yes ? String(localized: "Yes") : String(localized: "No")
        case .choice(let labels): return labels.joined(separator: ", ")
        case .score(let n): return String(n)
        }
    }
}

/// One answered question, optionally with confidence and per-option probabilities.
public struct DecisionAnswer: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var value: DecisionAnswerValue
    /// Overall confidence in `[0, 1]` when the provider reports it.
    public var confidence: Double?
    /// Per-option probability mass for `.choice` / `.noul` when available.
    public var probabilities: [String: Double]

    public init(
        id: String,
        value: DecisionAnswerValue,
        confidence: Double? = nil,
        probabilities: [String: Double] = [:]
    ) {
        self.id = id
        self.value = value
        self.confidence = confidence.map { min(1, max(0, $0)) }
        self.probabilities = probabilities
    }
}

/// Full provider response for a DecisionRequest.
public struct DecisionResponse: Codable, Sendable, Equatable {
    public var answers: [DecisionAnswer]
    /// Provider-reported overall confidence when answers omit per-answer confidence.
    public var confidence: Double?

    public init(answers: [DecisionAnswer], confidence: Double? = nil) {
        self.answers = answers
        self.confidence = confidence.map { min(1, max(0, $0)) }
    }

    public func answer(for questionID: String) -> DecisionAnswer? {
        answers.first { $0.id == questionID }
    }

    /// Effective confidence for branching: answer-level, else response-level, else `nil`.
    public func effectiveConfidence(for questionID: String) -> Double? {
        if let c = answer(for: questionID)?.confidence { return c }
        return confidence
    }
}

/// Compact presentation payload for the decision card / chips UI.
public struct DecisionPresentation: Codable, Sendable, Equatable {
    public var toolID: String
    public var toolTitle: String
    public var answers: [DecisionAnswer]
    public var confidence: Double?
    /// True when confidence is below the confirm threshold — UI should ask before acting.
    public var requiresConfirmation: Bool
    /// Optional reduce/filter paste payload from bulk tools (never an essay).
    public var pastePayload: String?
    /// Chip labels derived from answers for compact UI.
    public var chips: [String]

    public init(
        toolID: String,
        toolTitle: String,
        answers: [DecisionAnswer],
        confidence: Double? = nil,
        requiresConfirmation: Bool = false,
        pastePayload: String? = nil,
        chips: [String] = []
    ) {
        self.toolID = toolID
        self.toolTitle = toolTitle
        self.answers = answers
        self.confidence = confidence
        self.requiresConfirmation = requiresConfirmation
        self.pastePayload = pastePayload
        self.chips = chips.isEmpty ? answers.map(\.value.displayLabel) : chips
    }
}

/// Parses System One / Laya-shaped JSON into `DecisionResponse`.
public enum DecisionResponseParser {
    public static func parse(_ data: Data) throws -> DecisionResponse {
        let decoder = JSONDecoder()
        if let wire = try? decoder.decode(WireResponse.self, from: data) {
            return wire.toResponse()
        }
        // Tolerant: accept a single answer object.
        if let single = try? decoder.decode(WireAnswer.self, from: data) {
            return DecisionResponse(answers: [single.toAnswer()], confidence: single.confidence)
        }
        throw DecisionParseError.unreadable
    }

    public static func parse(jsonString: String) throws -> DecisionResponse {
        guard let data = jsonString.data(using: .utf8) else { throw DecisionParseError.unreadable }
        return try parse(data)
    }

    public enum DecisionParseError: Error, LocalizedError, Equatable {
        case unreadable
        case missingAnswers

        public var errorDescription: String? {
            switch self {
            case .unreadable: return String(localized: "The decision provider returned an unreadable response.")
            case .missingAnswers: return String(localized: "The decision provider returned no answers.")
            }
        }
    }

    struct WireResponse: Codable {
        var answers: [WireAnswer]?
        var confidence: Double?
        // Some adapters nest under `data`.
        var data: Nested?

        struct Nested: Codable {
            var answers: [WireAnswer]?
            var confidence: Double?
        }

        func toResponse() -> DecisionResponse {
            let raw = answers ?? data?.answers ?? []
            let conf = confidence ?? data?.confidence
            return DecisionResponse(answers: raw.map { $0.toAnswer() }, confidence: conf)
        }
    }

    struct WireAnswer: Codable {
        var id: String?
        var value: WireValue?
        var answer: WireValue?
        var confidence: Double?
        var probabilities: [String: Double]?
        var probs: [String: Double]?
        // Shorthand fields
        var noul: Bool?
        var choice: String?
        var choices: [String]?
        var score: Int?

        enum WireValue: Codable {
            case bool(Bool)
            case int(Int)
            case string(String)
            case strings([String])

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let b = try? c.decode(Bool.self) { self = .bool(b); return }
                if let i = try? c.decode(Int.self) { self = .int(i); return }
                if let s = try? c.decode(String.self) { self = .string(s); return }
                if let a = try? c.decode([String].self) { self = .strings(a); return }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported answer value")
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .bool(let b): try c.encode(b)
                case .int(let i): try c.encode(i)
                case .string(let s): try c.encode(s)
                case .strings(let a): try c.encode(a)
                }
            }
        }

        func toAnswer() -> DecisionAnswer {
            let qid = id ?? "primary"
            let probs = probabilities ?? probs ?? [:]
            if let noul {
                return DecisionAnswer(id: qid, value: .noul(noul), confidence: confidence, probabilities: probs)
            }
            if let choices {
                return DecisionAnswer(id: qid, value: .choice(choices), confidence: confidence, probabilities: probs)
            }
            if let choice {
                return DecisionAnswer(id: qid, value: .choice([choice]), confidence: confidence, probabilities: probs)
            }
            if let score {
                return DecisionAnswer(id: qid, value: .score(score), confidence: confidence, probabilities: probs)
            }
            let raw = value ?? answer
            switch raw {
            case .bool(let b):
                return DecisionAnswer(id: qid, value: .noul(b), confidence: confidence, probabilities: probs)
            case .int(let i):
                return DecisionAnswer(id: qid, value: .score(i), confidence: confidence, probabilities: probs)
            case .string(let s):
                return DecisionAnswer(id: qid, value: .choice([s]), confidence: confidence, probabilities: probs)
            case .strings(let a):
                return DecisionAnswer(id: qid, value: .choice(a), confidence: confidence, probabilities: probs)
            case .none:
                return DecisionAnswer(id: qid, value: .choice([]), confidence: confidence, probabilities: probs)
            }
        }
    }
}
