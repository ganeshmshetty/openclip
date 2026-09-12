// ActionDuplicator.swift
// OpenClip
//
// Duplicates a custom action or an installed extension and files the copy next to the original:
// same position in the popup bar order, same group. Lives here rather than in the Customize
// list's coordinator because the copy is made from the action's own page now.

import Core

enum ActionDuplicator {
    /// Returns the copy's id, or nil when the action cannot be duplicated or the copy failed (the
    /// failure is reported in the window).
    @MainActor
    static func duplicate(actionID id: String) async -> String? {
        let coordinator = ActionCoordinator.shared
        guard let action = coordinator.actions.first(where: { $0.id == id }),
              ActionIdentity.canDuplicate(action) else { return nil }

        if action.chrome.source == .custom {
            return coordinator.duplicateCustomAction(actionID: id)?.id
        }

        guard case .extensionPkg = action.chrome.source else { return nil }
        do {
            let newActionID = try await ExtensionManager.shared.duplicateExtension(actionID: id)
            coordinator.insertActionOrderAfter(newID: newActionID, originalID: id)
            for def in coordinator.actionGroupDefs {
                if let index = def.memberActionIDs.firstIndex(of: id) {
                    coordinator.addToGroup(actionID: newActionID, groupID: def.id, atIndex: index + 1)
                    break
                }
            }
            return newActionID
        } catch {
            Log.extensions.error("Failed to duplicate extension '\(id, privacy: .public)': \(error.localizedDescription)")
            SettingsRouter.shared.notifyError(
                title: String(localized: "Duplicate Failed"),
                message: String(localized: "OpenClip could not duplicate extension: \(error.localizedDescription)")
            )
            return nil
        }
    }
}
