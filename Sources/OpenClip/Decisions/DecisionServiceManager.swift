// DecisionServiceManager.swift
// OpenClip
//
// Manages Decision provider selection, secrets, presets, and evaluation (peer to AIServiceManager).
import Foundation
import os
import SwiftUI
import Core

extension Notification.Name {
    public static let decisionToolPresetsDidChange = Notification.Name("OpenClip.DecisionToolPresetsDidChange")
}

@MainActor
public final class DecisionServiceManager: ObservableObject {
    public static let shared = DecisionServiceManager()

    private let settingsStore = DefaultSettingsStore.shared
    private static let jevAPIKeyAccount = "decisionJevAPIKey"
    private static let openRouterAPIKeyAccount = "decisionOpenRouterAPIKey"
    private static let presetDecodeFailureLogged = OSAllocatedUnfairLock(initialState: false)

    public var isDecisionsEnabled: Bool {
        get { settingsStore.get(.isDecisionsEnabled) }
        set { objectWillChange.send(); settingsStore.set(.isDecisionsEnabled, value: newValue) }
    }

    public var liveAssistEnabled: Bool {
        get { settingsStore.get(.decisionLiveAssistEnabled) }
        set { objectWillChange.send(); settingsStore.set(.decisionLiveAssistEnabled, value: newValue) }
    }

    public var activeProviderRaw: String {
        get { settingsStore.get(.decisionActiveProvider) }
        set { objectWillChange.send(); settingsStore.set(.decisionActiveProvider, value: newValue) }
    }

    public var jevBaseURL: String {
        get { settingsStore.get(.decisionJevBaseURL) }
        set { objectWillChange.send(); settingsStore.set(.decisionJevBaseURL, value: newValue) }
    }

    public var openRouterBaseURL: String {
        get { settingsStore.get(.decisionOpenRouterBaseURL) }
        set { objectWillChange.send(); settingsStore.set(.decisionOpenRouterBaseURL, value: newValue) }
    }

    public var openRouterModel: String {
        get { settingsStore.get(.decisionOpenRouterModel) }
        set { objectWillChange.send(); settingsStore.set(.decisionOpenRouterModel, value: newValue) }
    }

    public var layaCommand: String {
        get { settingsStore.get(.decisionLayaCommand) }
        set { objectWillChange.send(); settingsStore.set(.decisionLayaCommand, value: newValue) }
    }

    public var liveAssistDebounceMS: Int {
        get { Int(settingsStore.get(.decisionLiveAssistDebounceMS)) ?? 200 }
        set {
            let clamped = min(300, max(100, newValue))
            objectWillChange.send()
            settingsStore.set(.decisionLiveAssistDebounceMS, value: String(clamped))
        }
    }

    public var toolsJSON: String {
        get { settingsStore.get(.decisionToolPresetsJSON) }
        set { objectWillChange.send(); settingsStore.set(.decisionToolPresetsJSON, value: newValue) }
    }

    @Published public var jevAPIKey: String {
        didSet {
            if jevAPIKey.isEmpty {
                SecretStore.delete(account: Self.jevAPIKeyAccount)
            } else if !SecretStore.set(jevAPIKey, account: Self.jevAPIKeyAccount) {
                Log.decisions.error("Failed to persist Jev API key; reverting.")
                jevAPIKey = oldValue
            }
        }
    }

    @Published public var openRouterAPIKey: String {
        didSet {
            if openRouterAPIKey.isEmpty {
                SecretStore.delete(account: Self.openRouterAPIKeyAccount)
            } else if !SecretStore.set(openRouterAPIKey, account: Self.openRouterAPIKeyAccount) {
                Log.decisions.error("Failed to persist OpenRouter decision API key; reverting.")
                openRouterAPIKey = oldValue
            }
        }
    }

    public var activeProviderType: DecisionProviderType {
        get { DecisionProviderType(rawValue: activeProviderRaw) ?? .laya }
        set { activeProviderRaw = newValue.rawValue }
    }

    public var providerOverride: (any DecisionProvider)?

    public var tools: [DecisionToolPreset] {
        get {
            guard !toolsJSON.isEmpty, let data = toolsJSON.data(using: .utf8) else {
                return DecisionDefaultPresets.all
            }
            if let decoded = try? JSONDecoder().decode([DecisionToolPreset].self, from: data) {
                return decoded
            }
            Self.presetDecodeFailureLogged.withLock { already in
                guard !already else { return }
                already = true
                Log.decisions.error("Failed to decode Decision tool presets; using defaults")
            }
            return DecisionDefaultPresets.all
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                toolsJSON = str
            } else {
                Log.decisions.error("Failed to encode Decision tool presets")
            }
            NotificationCenter.default.post(name: .decisionToolPresetsDidChange, object: self)
        }
    }

    public var enabledTools: [DecisionToolPreset] {
        let list = tools.filter(\.isEnabled)
        return list.isEmpty ? [DecisionDefaultPresets.all[0]] : list
    }

    private init() {
        self.jevAPIKey = SecretStore.get(account: Self.jevAPIKeyAccount) ?? ""
        self.openRouterAPIKey = SecretStore.get(account: Self.openRouterAPIKeyAccount) ?? ""
    }

    public func updateTool(_ updated: DecisionToolPreset) {
        var current = tools
        if let idx = current.firstIndex(where: { $0.id == updated.id }) {
            current[idx] = updated
        } else {
            current.append(updated)
        }
        tools = current
    }

    public func deleteTool(id: String) {
        var list = tools
        list.removeAll { $0.id == id }
        tools = list
    }

    public func duplicateTool(id: String) -> DecisionToolPreset? {
        guard let source = tools.first(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = "custom_\(UUID().uuidString.prefix(8))"
        copy.title = source.title + " Copy"
        updateTool(copy)
        return copy
    }

    public func moveTool(id: String, toGap gapIndex: Int) {
        let reordered = Self.reordering(tools, moving: id, toGap: gapIndex)
        guard reordered.map(\.id) != tools.map(\.id) else { return }
        tools = reordered
    }

    public static func reordering(_ tools: [DecisionToolPreset], moving id: String, toGap gapIndex: Int) -> [DecisionToolPreset] {
        guard let sourceIndex = tools.firstIndex(where: { $0.id == id }) else { return tools }
        var list = tools
        list.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: max(0, min(gapIndex, tools.count)))
        return list
    }

    public static func makeCustomTool(title: String, questions: [DecisionQuestion]) -> DecisionToolPreset {
        DecisionToolPreset(
            id: "custom_\(UUID().uuidString.prefix(8))",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            questions: questions,
            isEnabled: true
        )
    }

    public func resetToolsToDefault() {
        tools = DecisionDefaultPresets.all
    }

    public func tool(forActionID actionID: String) -> DecisionToolPreset? {
        let prefix = "decision.tool."
        guard actionID.hasPrefix(prefix) else { return nil }
        let toolID = String(actionID.dropFirst(prefix.count))
        return tools.first { $0.id == toolID }
    }

    public var currentProvider: any DecisionProvider {
        if let providerOverride { return providerOverride }
        switch activeProviderType {
        case .jev:
            return JevDecisionProvider(apiKey: jevAPIKey, baseURL: jevBaseURL)
        case .openRouter:
            return OpenRouterDecisionProvider(apiKey: openRouterAPIKey, baseURL: openRouterBaseURL, model: openRouterModel)
        case .laya:
            return LayaDecisionProvider(command: layaCommand)
        }
    }

    /// Preferred provider for Live assist: Laya when available, else the active provider.
    public func liveAssistProvider() async -> any DecisionProvider {
        let laya = LayaDecisionProvider(command: layaCommand)
        if case .available = await laya.availability() {
            return laya
        }
        return currentProvider
    }

    public func providerStatus() async -> DecisionProviderAvailability {
        await currentProvider.availability()
    }

    /// Evaluate a tool against selection text, including optional tree walk and bulk map/reduce.
    public func evaluate(tool: DecisionToolPreset, text: String) async throws -> DecisionPresentation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DecisionError.emptyInput }

        if let kind = tool.bulkMode.unitKind {
            return try await evaluateBulk(tool: tool, text: trimmed, kind: kind)
        }

        let provider = currentProvider
        let primaryQuestions = tool.questions
        guard let first = primaryQuestions.first else {
            throw DecisionError.invalidResponse
        }

        if let tree = DecisionBuiltinTrees.tree(id: tool.treeID) {
            return try await evaluateTree(tool: tool, text: trimmed, tree: tree, provider: provider)
        }

        let request = DecisionQuestionPacker.pack(state: trimmed, questions: primaryQuestions, toolID: tool.id)
        let response = try await provider.decide(request)
        guard let answer = response.answers.first ?? response.answer(for: first.id) else {
            throw DecisionError.invalidResponse
        }
        let confidence = response.effectiveConfidence(for: answer.id) ?? response.confidence
        if let confidence, confidence < tool.failBelowConfidence {
            throw DecisionError.lowConfidence
        }
        let needsConfirm = (confidence ?? 1) < tool.confirmBelowConfidence
        return DecisionPresentation(
            toolID: tool.id,
            toolTitle: tool.title,
            answers: response.answers.isEmpty ? [answer] : response.answers,
            confidence: confidence,
            requiresConfirmation: needsConfirm
        )
    }

    private func evaluateTree(
        tool: DecisionToolPreset,
        text: String,
        tree: DecisionTree,
        provider: any DecisionProvider
    ) async throws -> DecisionPresentation {
        var currentID = tree.rootID
        var depth = 0
        var collected: [DecisionAnswer] = []
        var lastConfidence: Double?

        while depth <= tree.depthCap {
            guard let node = tree.node(currentID) else { throw DecisionError.invalidResponse }
            if node.isTerminal {
                return DecisionPresentation(
                    toolID: tool.id,
                    toolTitle: tool.title,
                    answers: collected,
                    confidence: lastConfidence,
                    requiresConfirmation: (lastConfidence ?? 1) < tool.confirmBelowConfidence,
                    chips: [node.terminalLabel ?? collected.last?.value.displayLabel ?? tool.title]
                )
            }
            let request = DecisionQuestionPacker.pack(state: text, questions: [node.question], toolID: tool.id)
            let response = try await provider.decide(request)
            guard let answer = response.answers.first else { throw DecisionError.invalidResponse }
            collected.append(answer)
            lastConfidence = response.effectiveConfidence(for: answer.id) ?? response.confidence
            let outcome = DecisionTreeStepper.step(tree: tree, currentNodeID: currentID, answer: answer, depth: depth)
            switch outcome {
            case .continueTo(let next):
                currentID = next
                depth += 1
            case .fanOut(let children):
                // Fan-out before reveal: evaluate children, keep highest-confidence terminal path.
                var best: (label: String, confidence: Double, answers: [DecisionAnswer])?
                for childID in children {
                    guard let child = tree.node(childID) else { continue }
                    let childReq = DecisionQuestionPacker.pack(state: text, questions: [child.question], toolID: tool.id)
                    let childResp = try await provider.decide(childReq)
                    guard let childAnswer = childResp.answers.first else { continue }
                    let conf = childResp.effectiveConfidence(for: childAnswer.id) ?? 0
                    if child.isTerminal {
                        if best == nil || conf > (best?.confidence ?? -1) {
                            best = (child.terminalLabel ?? childAnswer.value.displayLabel, conf, collected + [childAnswer])
                        }
                    } else {
                        let stepped = DecisionTreeStepper.step(tree: tree, currentNodeID: childID, answer: childAnswer, depth: depth + 1)
                        if case .terminal(let label) = stepped, best == nil || conf > (best?.confidence ?? -1) {
                            best = (label, conf, collected + [childAnswer])
                        }
                    }
                }
                guard let best else { throw DecisionError.lowConfidence }
                return DecisionPresentation(
                    toolID: tool.id,
                    toolTitle: tool.title,
                    answers: best.answers,
                    confidence: best.confidence,
                    requiresConfirmation: best.confidence < tool.confirmBelowConfidence,
                    chips: [best.label]
                )
            case .terminal(let label):
                return DecisionPresentation(
                    toolID: tool.id,
                    toolTitle: tool.title,
                    answers: collected,
                    confidence: lastConfidence,
                    requiresConfirmation: (lastConfidence ?? 1) < tool.confirmBelowConfidence,
                    chips: [label]
                )
            case .failClosed:
                throw DecisionError.lowConfidence
            }
        }
        throw DecisionError.lowConfidence
    }

    private func evaluateBulk(
        tool: DecisionToolPreset,
        text: String,
        kind: DecisionBulkUnitKind
    ) async throws -> DecisionPresentation {
        let limits = DecisionBulkLimits.default
        let units = DecisionBulkReducer.split(text, kind: kind, limits: limits)
        guard !units.isEmpty else { throw DecisionError.emptyInput }
        let provider = currentProvider
        let started = Date()
        var judgments: [DecisionBulkJudgment] = []
        var answers: [DecisionAnswer] = []

        for unit in units {
            let elapsed = Date().timeIntervalSince(started)
            guard DecisionBulkReducer.withinBudget(elapsed: elapsed, limits: limits) else {
                throw DecisionError.bulkBudgetExceeded
            }
            let question = tool.questions.first ?? .noul(id: "clean.keep", prompt: String(localized: "Keep this item?"))
            let request = DecisionQuestionPacker.pack(state: unit.text, questions: [question], toolID: tool.id)
            let response = try await provider.decide(request)
            guard let answer = response.answers.first else { continue }
            answers.append(answer)
            let keep: Bool
            switch answer.value {
            case .noul(let yes): keep = yes
            case .choice(let labels): keep = !(labels.first?.lowercased().contains("ignore") ?? false)
            case .score(let n): keep = n >= 3
            }
            judgments.append(DecisionBulkJudgment(unitID: unit.id, keep: keep, mark: keep ? nil : "drop", confidence: answer.confidence))
        }

        let reduced = DecisionBulkReducer.reduce(units: units, judgments: judgments)
        let confidences = judgments.compactMap(\.confidence)
        let avg = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
        return DecisionPresentation(
            toolID: tool.id,
            toolTitle: tool.title,
            answers: answers,
            confidence: avg,
            requiresConfirmation: (avg ?? 1) < tool.confirmBelowConfidence,
            pastePayload: reduced.paste,
            chips: [
                String(localized: "Kept \(judgments.filter(\.keep).count)/\(units.count)"),
                String(localized: "Dropped \(judgments.filter { !$0.keep }.count)")
            ]
        )
    }
}
