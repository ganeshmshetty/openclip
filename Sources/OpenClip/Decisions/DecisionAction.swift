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

    public static let actionIDPrefix = "decision.tool."

    public static func actionID(forToolID toolID: String) -> String { actionIDPrefix + toolID }

    public var id: String { Self.actionID(forToolID: toolID) }

    /// Resolved like any other action icon, so a tool can use an SF Symbol, an Iconify icon or
    /// a file the user added; an unset icon falls back to the Decision seal.
    public var icon: ActionIcon {
        ActionIcon.resolve(from: symbolName?.isEmpty == false ? symbolName : Constants.defaultDecisionIconSymbol)
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
        // A bulk tool's filtered list is ordinary returned text: pasted, copied or previewed by
        // the user's delivery preference like any other action. Everything else is shown inline
        // on the tool's own icon (see PopupModeStore.decisionStates); there is no card.
        if let payload = presentation.pastePayload, !payload.isEmpty {
            return .text(payload)
        }
        return .decision(presentation)
    }

    @MainActor
    private func tool() -> DecisionToolPreset? {
        DecisionServiceManager.shared.tools.first { $0.id == toolID }
    }
}
