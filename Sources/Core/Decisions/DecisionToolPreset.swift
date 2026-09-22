// DecisionToolPreset.swift
// OpenClip
//
// User-configurable Decision tool presets — first-class peers to AIActionPreset.
import Foundation

/// How a Decision tool maps over a multi-unit selection.
public enum DecisionBulkMode: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case line
    case row
    case word
    case span
    case paragraph

    public var unitKind: DecisionBulkUnitKind? {
        switch self {
        case .none: return nil
        case .line: return .line
        case .row: return .row
        case .word: return .word
        case .span: return .span
        case .paragraph: return .paragraph
        }
    }
}

public struct DecisionToolPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var isEnabled: Bool
    /// Primary questions asked of the selection (usually one).
    public var questions: [DecisionQuestion]
    public var bulkMode: DecisionBulkMode
    /// Confidence at or above this may auto-act; below requires confirm.
    public var confirmBelowConfidence: Double
    /// Confidence below this fails closed (no act).
    public var failBelowConfidence: Double
    /// SF Symbol hint for chrome (optional).
    public var symbolName: String?
    /// Answers continuously in the floating Quick Assist window as the user types, instead of
    /// only when the tool is clicked. Trees and bulk tools are excluded there: they are
    /// deliberate, multi-request runs.
    public var showsInQuickAssist: Bool

    public init(
        id: String,
        title: String,
        questions: [DecisionQuestion],
        isEnabled: Bool = true,
        bulkMode: DecisionBulkMode = .none,
        confirmBelowConfidence: Double = 0.72,
        failBelowConfidence: Double = 0.40,
        symbolName: String? = nil,
        showsInQuickAssist: Bool = false
    ) {
        self.id = id
        self.title = title
        self.questions = questions
        self.isEnabled = isEnabled
        self.bulkMode = bulkMode
        self.confirmBelowConfidence = confirmBelowConfidence
        self.failBelowConfidence = failBelowConfidence
        self.symbolName = symbolName
        self.showsInQuickAssist = showsInQuickAssist
    }

    /// Tolerant decoding: presets are persisted as JSON, so one saved by an older build is
    /// missing every key added since. Defaulting each field keeps the user's custom tools
    /// instead of failing the whole list back to the shipped defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? id
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        questions = try container.decodeIfPresent([DecisionQuestion].self, forKey: .questions) ?? []
        bulkMode = try container.decodeIfPresent(DecisionBulkMode.self, forKey: .bulkMode) ?? .none
        confirmBelowConfidence = try container.decodeIfPresent(Double.self, forKey: .confirmBelowConfidence) ?? 0.72
        failBelowConfidence = try container.decodeIfPresent(Double.self, forKey: .failBelowConfidence) ?? 0.40
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName)
        showsInQuickAssist = try container.decodeIfPresent(Bool.self, forKey: .showsInQuickAssist) ?? false
    }
}

public enum DecisionDefaultPresets {
    public static let all: [DecisionToolPreset] = [
        DecisionToolPreset(
            id: "smart_action",
            title: String(localized: "Smart action"),
            questions: [
                .choice(
                    id: "smart.next",
                    prompt: String(localized: "What is the best next action for this selection?"),
                    options: [
                        String(localized: "Reply"),
                        String(localized: "Forward"),
                        String(localized: "File"),
                        String(localized: "Schedule"),
                        String(localized: "Ignore")
                    ]
                )
            ],
            symbolName: "lightbulb.max"
        ),
        DecisionToolPreset(
            id: "triage",
            title: String(localized: "Triage"),
            questions: [
                .choice(
                    id: "triage.bucket",
                    prompt: String(localized: "Which triage bucket fits this selection?"),
                    options: [
                        String(localized: "Urgent"),
                        String(localized: "Important"),
                        String(localized: "Later"),
                        String(localized: "Ignore")
                    ]
                )
            ],
            symbolName: "tray.full"
        ),
        DecisionToolPreset(
            id: "reply_as",
            title: String(localized: "Reply as…"),
            questions: [
                .choice(
                    id: "reply.tone",
                    prompt: String(localized: "Which reply tone fits?"),
                    options: [
                        String(localized: "Friendly"),
                        String(localized: "Formal"),
                        String(localized: "Brief"),
                        String(localized: "Assertive")
                    ]
                )
            ],
            symbolName: "text.bubble"
        ),
        DecisionToolPreset(
            id: "send_to",
            title: String(localized: "Send to…"),
            questions: [
                .choice(
                    id: "send.dest",
                    prompt: String(localized: "Where should this go?"),
                    options: [
                        String(localized: "Notes"),
                        String(localized: "Tasks"),
                        String(localized: "Calendar"),
                        String(localized: "Email"),
                        String(localized: "Nowhere")
                    ]
                )
            ],
            symbolName: "paperplane"
        ),
        DecisionToolPreset(
            id: "safe_to_share",
            title: String(localized: "Safe to share?"),
            questions: [
                .noul(
                    id: "share.safe",
                    prompt: String(localized: "Is this selection safe to share externally?")
                )
            ],
            confirmBelowConfidence: 0.85,
            failBelowConfidence: 0.50,
            symbolName: "lock.shield",
            showsInQuickAssist: true
        ),
        DecisionToolPreset(
            id: "fix_path",
            title: String(localized: "Fix path"),
            questions: [
                .choice(
                    id: "fix.strategy",
                    prompt: String(localized: "Best fix path for this issue?"),
                    options: [
                        String(localized: "Quick patch"),
                        String(localized: "Refactor"),
                        String(localized: "Revert"),
                        String(localized: "Investigate more")
                    ]
                )
            ],
            symbolName: "wrench.and.screwdriver"
        ),
        DecisionToolPreset(
            id: "clean_this_list",
            title: String(localized: "Clean this list"),
            questions: [
                .noul(
                    id: "clean.keep",
                    prompt: String(localized: "Keep this list item?")
                )
            ],
            bulkMode: .line,
            symbolName: "checklist"
        )
    ]
}
