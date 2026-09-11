// AIActionSync.swift
// OpenClip
//
// Keeps AIServiceManager's AI presets registered in the ActionCoordinator as individual
// `AIAction`s, so every preset shows up as a searchable entry in the action-search palette and
// as its own row in Preferences → Actions (while staying out of the popup bar — the reorderable
// `builtin.aiTools` action is the bar's AI entry point). Also registers that AI Tools launcher.
// Reconciles the registered set whenever the preset list changes; the title snapshot on
// `AIAction` is refreshed by re-registering on any content change, and a changed *order* is
// re-registered from scratch so the catalog (palette, AI sub-bar) follows the user's ordering.
import Foundation
import Core

@MainActor
public final class AIActionSync {
    public static let shared = AIActionSync()

    private let coordinator = ActionCoordinator.shared
    /// The preset ids currently registered, in the order they were registered. Order matters:
    /// the catalog position of the AI actions (and so the palette / AI sub-bar order) follows it.
    private var registeredOrder: [String] = []
    private var lastFingerprint: [String] = []
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .aiActionPresetsDidChange,
            object: AIServiceManager.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
        // The Ask… entry goes in ahead of the presets so it leads the AI Tools bar and the
        // scoped palette; the reconciliation below leaves it alone.
        coordinator.register(action: AskAIAction())
        sync()
        coordinator.register(action: AIToolsAction())
    }

    /// Reconciles the registered AI actions against the current preset list. Cheap when nothing
    /// changed (single fingerprint compare), so it is safe to call from any display surface too.
    public func sync() {
        let presets = AIServiceManager.shared.presets
        let fingerprint = presets.map { "\($0.id)|\($0.title)|\($0.prompt)|\($0.isEnabled)" }
        guard fingerprint != lastFingerprint else { return }

        let currentOrder = presets.map { AIAction(presetID: $0.id, title: $0.title).id }

        if currentOrder != registeredOrder {
            // The user reordered (or added/removed) presets. Replace all AI actions atomically
            // in list order so the catalog and palette follow the new order without cascading
            // notifications.
            let newAIActions = presets.map { AIAction(presetID: $0.id, title: $0.title) }
            coordinator.replaceActions(
                matching: { ActionIdentity.isAIPreset($0) && !($0 is any InstructionPromptingAction) },
                with: newAIActions
            )
        } else {
            // Same presets in the same order — only titles/prompts/enabled state changed, so an
            // in-place refresh is enough (and leaves the catalog undisturbed).
            for preset in presets {
                coordinator.register(action: AIAction(presetID: preset.id, title: preset.title))
            }
        }

        registeredOrder = currentOrder
        lastFingerprint = fingerprint
    }
}
