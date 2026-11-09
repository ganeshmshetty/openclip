// ContextualPolicy.swift
// OpenClip
//
// Resolves contextual promotion from explicit author intent and the uniform narrowing-requirement rule.
// User settings (global toggle, per-action disable) are applied by the registry and views outside this policy.
import Foundation

public enum ContextualReason: Sendable, Equatable {
    case explicitTrue
    case explicitFalse
    case narrowingRequirement
    case automaticTrigger
    case builtIn
    case standard
}

public struct ContextualDecision: Sendable, Equatable {
    public let isContextual: Bool
    public let reason: ContextualReason

    public init(isContextual: Bool, reason: ContextualReason) {
        self.isContextual = isContextual
        self.reason = reason
    }
}

public enum ContextualPolicy {
    public static func decision(for action: any Action) -> ContextualDecision {
        if let explicit = action.chrome.contextualOverride {
            return ContextualDecision(isContextual: explicit, reason: explicit ? .explicitTrue : .explicitFalse)
        }

        let underlying = ContextualActionClassifier.unwrap(action)
        if let rules = (underlying as? any ActionWithRules)?.rules,
           rules.requirements?.declaresNarrowingRequirement == true {
            return ContextualDecision(isContextual: true, reason: .narrowingRequirement)
        }

        if ContextualActionClassifier.isBuiltInContextual(underlying.id) {
            return ContextualDecision(isContextual: true, reason: .builtIn)
        }

        if ContextualActionClassifier.hasAutomaticTrigger(action) {
            return ContextualDecision(isContextual: true, reason: .automaticTrigger)
        }

        return ContextualDecision(isContextual: false, reason: .standard)
    }
}
