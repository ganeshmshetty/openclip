// DecisionToolsAction.swift
// OpenClip
//
// "Decision Tools" bar launcher — first-class peer to AIToolsAction.
import Foundation
import Core

public struct DecisionToolsAction: Action, SubActionProviding {
    public init() {}

    public var id: String { "builtin.decisionTools" }
    public var title: String { String(localized: "Decision Tools") }
    public var icon: ActionIcon { .symbol(Constants.defaultDecisionIconSymbol) }
    public var chrome: ActionChrome {
        ActionChrome(
            badge: .none,
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .builtin,
            launchesDecisions: true
        )
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        DecisionServiceManager.shared.isDecisionsEnabled
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }

    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        let presets = catalog.filter { ActionIdentity.isDecisionPreset($0) }
        if !presets.isEmpty { return presets }
        return DecisionServiceManager.shared.enabledTools.map {
            DecisionAction(toolID: $0.id, title: $0.title, symbolName: $0.symbolName)
        }
    }
}
