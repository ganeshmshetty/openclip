// DecisionAction.swift
// OpenClip
//
// Registry action for one Decision tool preset (peer to AIAction).
import Foundation
import Core

public struct DecisionAction: Action {
    public let toolID: String
    public let title: String
    public let symbolName: String?

    public var id: String { "decision.tool.\(toolID)" }

    public var icon: ActionIcon {
        .symbol(symbolName ?? Constants.defaultDecisionIconSymbol)
    }

    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .decision)
    }

    public init(toolID: String, title: String, symbolName: String? = nil) {
        self.toolID = toolID
        self.title = title
        self.symbolName = symbolName
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard DecisionServiceManager.shared.isDecisionsEnabled else { return false }
        return tool()?.isEnabled ?? false
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard let tool = tool() else { return .success }
        let presentation = try await DecisionServiceManager.shared.evaluate(
            tool: tool,
            text: context.selection.text
        )
        return .decision(presentation)
    }

    @MainActor
    private func tool() -> DecisionToolPreset? {
        DecisionServiceManager.shared.tools.first { $0.id == toolID }
    }
}
