// VisibilityPredicate.swift
// OpenClip
//
// Decorator and host seam for extension visibility predicates. The evaluator lives in the app target;
// Core only decides when to call it and how to combine its answer with the base action's gates.
import Foundation

/// One predicate evaluation request. The host runtime resolves `predicatePath` inside `packageRoot`.
public struct VisibilityPredicateRequest: Sendable {
    public let actionID: String
    public let predicatePath: String
    public let packageRoot: URL
    public let packageID: String
    public let requirements: ActionRequirements?
    public let legacyRegex: String?
    public let context: ActionContext

    public init(
        actionID: String,
        predicatePath: String,
        packageRoot: URL,
        packageID: String,
        requirements: ActionRequirements?,
        legacyRegex: String?,
        context: ActionContext
    ) {
        self.actionID = actionID
        self.predicatePath = predicatePath
        self.packageRoot = packageRoot
        self.packageID = packageID
        self.requirements = requirements
        self.legacyRegex = legacyRegex
        self.context = context
    }
}

/// Host-side predicate runtime. Returns nil when the predicate could not run; callers fail open.
public protocol VisibilityPredicateEvaluating: Sendable {
    @MainActor func evaluate(_ request: VisibilityPredicateRequest) -> Bool?
}

/// Wraps an extension action with `requirements.predicate`. Identity and behavior forward to the
/// base action; `isEnabled` combines the base gates with the predicate's fail-open answer.
public struct PredicateDecoratedAction: Action, ActionWithRules, ConfigurableAction, SubActionProviding {
    public let base: any Action
    public let rules: ExtensionActionRules?
    public let predicatePath: String
    public let packageRoot: URL
    public let packageID: String
    public let evaluator: any VisibilityPredicateEvaluating

    public init(
        base: any Action,
        rules: ExtensionActionRules?,
        predicatePath: String,
        packageRoot: URL,
        packageID: String,
        evaluator: any VisibilityPredicateEvaluating
    ) {
        self.base = base
        self.rules = rules
        self.predicatePath = predicatePath
        self.packageRoot = packageRoot
        self.packageID = packageID
        self.evaluator = evaluator
    }

    public var id: String { base.id }
    public var title: String { base.title }
    public var icon: ActionIcon { base.icon }
    public var chrome: ActionChrome { base.chrome }
    public var actionOptions: [ExtensionOption] { base.actionOptions }
    public var keywords: [String] { base.keywords }
    public var delivery: ActionDelivery? { base.delivery }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        if let cached = context.visibilityMemo.result(for: base.id) { return cached }
        guard base.isEnabled(for: context) else {
            context.visibilityMemo.store(false, for: base.id)
            return false
        }
        let match = context.match ?? base.matchInfo(for: context)
        let predicateContext: ActionContext
        if context.match == nil, let match {
            predicateContext = ActionContext(
                selection: context.selection,
                modifiers: context.modifiers,
                isSecondaryClick: context.isSecondaryClick,
                match: match,
                pasteTargetAvailable: context.pasteTargetAvailable,
                visibilityMemo: context.visibilityMemo
            )
        } else {
            predicateContext = context
        }
        let request = VisibilityPredicateRequest(
            actionID: base.id,
            predicatePath: predicatePath,
            packageRoot: packageRoot,
            packageID: packageID,
            requirements: rules?.requirements,
            legacyRegex: rules?.legacyRegex,
            context: predicateContext
        )
        let result = evaluator.evaluate(request) ?? true
        context.visibilityMemo.store(result, for: base.id)
        return result
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        base.matchInfo(for: context)
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        try await base.perform(context)
    }

    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        (base as? any SubActionProviding)?.subActions(in: catalog) ?? []
    }

    public var preferenceIconName: String {
        if let configurable = base as? any ConfigurableAction {
            return configurable.preferenceIconName
        }
        switch base.icon {
        case .symbol(let name): return name
        case .local(let url): return url.lastPathComponent
        case .url(let url): return url.absoluteString
        case .text(let text): return text
        }
    }
}
