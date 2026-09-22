// DecisionBulkSession.swift
// OpenClip
//
// Drives one bulk run for the Bulk decision card: splits the selection into units, judges each one
// with the chosen tool, and files the results into categories the user can copy.
//
// A bulk run is one request per unit — every unit is a different piece of text, so unlike Quick
// Assist they cannot share a forward pass. The run is sequential (the local model serves one
// request at a time anyway), publishes progress after each unit, and can be cancelled, keeping
// whatever it has judged so far.
import Foundation
import AppKit
import Core

@MainActor
public final class DecisionBulkSession: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case finished
    }

    /// A category of results: yes/no/unsure for a yes-no tool, one per option for a choice tool.
    public struct Section: Identifiable, Equatable, Sendable {
        public var id: String { label }
        public var label: String
        public var items: [String]
    }

    public let text: String
    @Published public var mode: DecisionBulkUnitKind {
        didSet { if mode != oldValue { resplit() } }
    }
    @Published public var toolID: String {
        didSet { if toolID != oldValue { reset() } }
    }
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var units: [DecisionBulkUnit] = []
    /// Unit id to category label, filled in as the run progresses.
    @Published public private(set) var categories: [Int: String] = [:]
    @Published public private(set) var completed = 0
    /// Set when the whole run could not start (no provider, for instance).
    @Published public private(set) var errorMessage: String?

    private var runTask: Task<Void, Never>?
    private let limits: DecisionBulkLimits

    public static let unsureLabel = String(localized: "Unsure")
    public static let yesLabel = String(localized: "Yes")
    public static let noLabel = String(localized: "No")

    /// The modes offered in the card. Rows are lines of a list; words are individual terms.
    public static let offeredModes: [DecisionBulkUnitKind] = [.row, .word]

    public init(text: String, limits: DecisionBulkLimits = .interactive) {
        self.text = text
        self.limits = limits
        self.mode = .row
        self.toolID = Self.eligibleTools().first?.id ?? ""
        resplit()
    }

    // MARK: - Tools and units

    /// Tools a bulk run can use: enabled, single-question, not themselves a tree (a tree needs
    /// several round trips per unit) and not already a bulk preset.
    public static func eligibleTools() -> [DecisionToolPreset] {
        DecisionServiceManager.shared.tools.filter {
            $0.isEnabled && $0.treeID == nil && !$0.questions.isEmpty
        }
    }

    public var availableTools: [DecisionToolPreset] { Self.eligibleTools() }

    public var tool: DecisionToolPreset? {
        availableTools.first { $0.id == toolID } ?? availableTools.first
    }

    /// True when the selection produced more units than the cap, so the run is a prefix.
    public private(set) var wasTruncated = false

    private func resplit() {
        let all = DecisionBulkReducer.split(text, kind: mode, limits: DecisionBulkLimits(maxUnits: .max, budgetSeconds: limits.budgetSeconds))
        wasTruncated = all.count > limits.maxUnits
        units = Array(all.prefix(limits.maxUnits))
        reset()
    }

    private func reset() {
        runTask?.cancel()
        runTask = nil
        phase = .idle
        categories = [:]
        completed = 0
        errorMessage = nil
    }

    // MARK: - Running

    public func run() {
        guard phase != .running, let tool, !units.isEmpty else { return }
        runTask?.cancel()
        phase = .running
        completed = 0
        categories = [:]
        errorMessage = nil
        let units = self.units

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = DecisionServiceManager.shared.currentProvider
            guard let question = tool.questions.first else { return }
            for unit in units {
                if Task.isCancelled { break }
                do {
                    let request = DecisionQuestionPacker.pack(state: unit.text, questions: [question], toolID: tool.id)
                    let response = try await provider.decide(request)
                    self.categories[unit.id] = Self.category(for: response, tool: tool)
                } catch is CancellationError {
                    break
                } catch {
                    // One unit failing is not the run failing: file it as unsure and carry on, but
                    // surface the reason so a misconfigured provider is not silently "all unsure".
                    self.categories[unit.id] = Self.unsureLabel
                    if self.errorMessage == nil { self.errorMessage = error.localizedDescription }
                }
                self.completed += 1
            }
            self.phase = .finished
            self.runTask = nil
            Log.decisions.info("Bulk run finished: \(self.completed, privacy: .public)/\(units.count, privacy: .public) unit(s)")
        }
    }

    public func cancel() {
        runTask?.cancel()
        runTask = nil
        if phase == .running { phase = .finished }
    }

    /// The category one unit's answer belongs to, honouring the tool's confidence threshold.
    static func category(for response: DecisionResponse, tool: DecisionToolPreset) -> String {
        guard let answer = response.answers.first else { return unsureLabel }
        let confidence = answer.confidence ?? response.confidence
        if let confidence, confidence < tool.confirmBelowConfidence { return unsureLabel }
        switch answer.value {
        case .noul(let yes):
            return yes ? yesLabel : noLabel
        case .choice(let labels):
            guard let chosen = labels.first, !chosen.isEmpty else { return unsureLabel }
            // Snap back to a declared option so section labels stay stable even if the model
            // answers with different casing.
            let options = tool.questions.first?.options ?? []
            return options.first { $0.caseInsensitiveCompare(chosen) == .orderedSame } ?? chosen
        }
    }

    // MARK: - Results

    /// Every category this tool can produce, in a stable order, so the card shows them filling up
    /// while the run is in progress rather than re-ordering under the pointer.
    public var categoryLabels: [String] {
        guard let tool, let question = tool.questions.first else { return [Self.unsureLabel] }
        switch question.kind {
        case .noul:
            return [Self.yesLabel, Self.noLabel, Self.unsureLabel]
        case .choice:
            return question.options + [Self.unsureLabel]
        }
    }

    public var sections: [Section] {
        let byID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.text) })
        var grouped: [String: [String]] = [:]
        for unit in units {
            guard let label = categories[unit.id], let text = byID[unit.id] else { continue }
            grouped[label, default: []].append(text)
        }
        // Declared categories first, then anything the model invented, so nothing is ever dropped.
        let extras = grouped.keys.filter { !categoryLabels.contains($0) }.sorted()
        return (categoryLabels + extras).map { Section(label: $0, items: grouped[$0] ?? []) }
    }

    public var progressFraction: Double {
        units.isEmpty ? 0 : Double(completed) / Double(units.count)
    }

    // MARK: - Copying

    /// One category's items, one per line.
    public func copyText(for section: Section) -> String {
        section.items.joined(separator: "\n")
    }

    /// Every non-empty category with a heading, ready to paste somewhere else.
    public func copyAllText() -> String {
        sections
            .filter { !$0.items.isEmpty }
            .map { "## \($0.label) (\($0.items.count))\n" + $0.items.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }

    public func copyToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
