// DecisionTree.swift
// OpenClip
//
// Multi-step coarse→fine Decision trees with fan-out, fail-closed low confidence, and depth cap.
import Foundation

/// One node in a Decision tree: a question plus optional edges keyed by answer label.
public struct DecisionTreeNode: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var question: DecisionQuestion
    /// Maps normalized answer labels ("yes"/"no"/choice text/score string) to child node ids.
    public var edges: [String: String]
    /// When true, this node fans out to all listed children before revealing a final answer.
    public var fanOutChildIDs: [String]
    /// Terminal nodes produce the chip/label shown to the user.
    public var isTerminal: Bool
    public var terminalLabel: String?

    public init(
        id: String,
        question: DecisionQuestion,
        edges: [String: String] = [:],
        fanOutChildIDs: [String] = [],
        isTerminal: Bool = false,
        terminalLabel: String? = nil
    ) {
        self.id = id
        self.question = question
        self.edges = edges
        self.fanOutChildIDs = fanOutChildIDs
        self.isTerminal = isTerminal
        self.terminalLabel = terminalLabel
    }
}

public struct DecisionTree: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var rootID: String
    public var nodes: [String: DecisionTreeNode]
    /// Maximum steps before fail-closed abort.
    public var depthCap: Int
    /// Confidence below this fails closed (no auto-act / no continue).
    public var failClosedConfidence: Double

    public init(
        id: String,
        rootID: String,
        nodes: [DecisionTreeNode],
        depthCap: Int = 4,
        failClosedConfidence: Double = 0.45
    ) {
        self.id = id
        self.rootID = rootID
        self.nodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.depthCap = max(1, depthCap)
        self.failClosedConfidence = min(1, max(0, failClosedConfidence))
    }

    public func node(_ id: String) -> DecisionTreeNode? { nodes[id] }
}

public enum DecisionTreeStepOutcome: Sendable, Equatable {
    case continueTo(nodeID: String)
    case fanOut([String])
    case terminal(label: String)
    case failClosed(reason: String)
}

/// Pure stepper: given the latest answer, advance the tree.
public enum DecisionTreeStepper {
    public static func normalizeLabel(_ value: DecisionAnswerValue) -> String {
        switch value {
        case .noul(let yes): return yes ? "yes" : "no"
        case .choice(let labels): return (labels.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    public static func step(
        tree: DecisionTree,
        currentNodeID: String,
        answer: DecisionAnswer,
        depth: Int
    ) -> DecisionTreeStepOutcome {
        guard depth < tree.depthCap else {
            return .failClosed(reason: "Depth cap (\(tree.depthCap)) reached.")
        }
        guard let node = tree.node(currentNodeID) else {
            return .failClosed(reason: "Unknown node.")
        }
        if let confidence = answer.confidence, confidence < tree.failClosedConfidence {
            return .failClosed(reason: "Confidence \(String(format: "%.2f", confidence)) below threshold \(String(format: "%.2f", tree.failClosedConfidence)).")
        }
        if node.isTerminal {
            return .terminal(label: node.terminalLabel ?? answer.value.displayLabel)
        }
        if !node.fanOutChildIDs.isEmpty {
            return .fanOut(node.fanOutChildIDs)
        }
        let key = normalizeLabel(answer.value)
        if let next = node.edges[key] ?? node.edges[answer.value.displayLabel.lowercased()] {
            if let child = tree.node(next), child.isTerminal {
                return .terminal(label: child.terminalLabel ?? child.question.prompt)
            }
            return .continueTo(nodeID: next)
        }
        return .failClosed(reason: "No edge for answer “\(key)”.")
    }

    /// Walk a pre-answered path (tests / offline fixtures). Fails closed on first mismatch.
    public static func walk(
        tree: DecisionTree,
        answersByQuestionID: [String: DecisionAnswer]
    ) -> DecisionTreeStepOutcome {
        var current = tree.rootID
        var depth = 0
        var lastTerminal: DecisionTreeStepOutcome = .failClosed(reason: "Empty walk.")
        while depth <= tree.depthCap {
            guard let node = tree.node(current) else {
                return .failClosed(reason: "Unknown node \(current).")
            }
            if node.isTerminal {
                return .terminal(label: node.terminalLabel ?? node.id)
            }
            guard let answer = answersByQuestionID[node.question.id] else {
                return .failClosed(reason: "Missing answer for \(node.question.id).")
            }
            let outcome = step(tree: tree, currentNodeID: current, answer: answer, depth: depth)
            switch outcome {
            case .continueTo(let next):
                current = next
                depth += 1
                lastTerminal = outcome
            case .fanOut(let children):
                // Coarse→fine: take first surviving child that has an answer; else fail closed.
                for childID in children {
                    if let child = tree.node(childID), answersByQuestionID[child.question.id] != nil {
                        current = childID
                        depth += 1
                        lastTerminal = outcome
                        break
                    }
                }
                if case .fanOut = lastTerminal { return .failClosed(reason: "Fan-out produced no answered child.") }
            case .terminal, .failClosed:
                return outcome
            }
        }
        return .failClosed(reason: "Depth cap during walk.")
    }
}
