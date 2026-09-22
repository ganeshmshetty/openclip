// DecisionActionSync.swift
// OpenClip
//
// Keeps Decision tool presets registered in ActionCoordinator (peer to AIActionSync).
import Foundation
import Core

@MainActor
public final class DecisionActionSync {
    public static let shared = DecisionActionSync()

    private let coordinator = ActionCoordinator.shared
    private var registeredOrder: [String] = []
    private var lastFingerprint: [String] = []
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .decisionToolPresetsDidChange,
            object: DecisionServiceManager.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
        sync()
        coordinator.register(action: DecisionToolsAction())
    }

    public func sync() {
        let tools = DecisionServiceManager.shared.tools
        let fingerprint = tools.map { "\($0.id)|\($0.title)|\($0.isEnabled)|\($0.questions.count)" }
        guard fingerprint != lastFingerprint else { return }

        // "Bulk…" is a Decision-group member too, always last: it is the one entry that judges a
        // selection item by item rather than as a whole.
        let currentOrder = tools.map { DecisionAction(toolID: $0.id, title: $0.title, symbolName: $0.symbolName).id }
            + [DecisionBulkAction.actionID]

        if currentOrder != registeredOrder {
            let newActions: [any Action] = tools.map { DecisionAction(toolID: $0.id, title: $0.title, symbolName: $0.symbolName) }
                + [DecisionBulkAction()]
            coordinator.replaceActions(
                matching: { ActionIdentity.isDecisionPreset($0) },
                with: newActions
            )
        } else {
            for tool in tools {
                coordinator.register(action: DecisionAction(toolID: tool.id, title: tool.title, symbolName: tool.symbolName))
            }
            coordinator.register(action: DecisionBulkAction())
        }

        registeredOrder = currentOrder
        lastFingerprint = fingerprint
    }
}
