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

        let currentOrder = tools.map { DecisionAction(toolID: $0.id, title: $0.title, symbolName: $0.symbolName).id }

        if currentOrder != registeredOrder {
            let newActions = tools.map { DecisionAction(toolID: $0.id, title: $0.title, symbolName: $0.symbolName) }
            coordinator.replaceActions(
                matching: { ActionIdentity.isDecisionPreset($0) },
                with: newActions
            )
        } else {
            for tool in tools {
                coordinator.register(action: DecisionAction(toolID: tool.id, title: tool.title, symbolName: tool.symbolName))
            }
        }

        registeredOrder = currentOrder
        lastFingerprint = fingerprint
    }
}
