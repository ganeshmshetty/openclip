// ActionDeletion.swift
// OpenClip
//
// Deletes a custom action, an installed extension, or a custom group. Used by the Customize list's
// context menu; mirrors the action editor's Delete Action and the row trash button it replaced:
// a custom group ungroups, an extension uninstalls, and a custom action is removed from the store
// and its generated single-action manifest package is deleted from disk so it cannot re-register.

import Foundation
import Core
import KeyboardShortcuts

enum ActionDeletion {
    /// Whether the user may delete `action`: custom actions, installed extensions, and custom
    /// groups qualify; built-ins and AI presets do not.
    static func canDelete(_ action: any Action) -> Bool {
        if action.chrome.rowStyle == .actionGroup { return true }
        switch action.chrome.source {
        case .custom, .extensionPkg: return true
        case .builtin, .ai: return false
        }
    }

    /// Deletes the action with `id`, reporting failures in the settings window.
    @MainActor
    static func delete(actionID id: String) async {
        guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == id }) else { return }

        if action.chrome.rowStyle == .actionGroup {
            if case .extensionPkg = action.chrome.source {
                await uninstall(actionID: ActionIdentity.extensionPackageID(of: action) ?? id)
            } else {
                ActionCoordinator.shared.ungroup(groupID: id)
            }
            return
        }

        switch action.chrome.source {
        case .custom:
            KeyboardShortcuts.reset(.actionHotkey(id))
            ActionCoordinator.shared.deleteCustomAction(actionID: id)
            ActionCustomizationManager.shared.resetOverride(for: id)
            SettingsRouter.shared.clearConfigurationRequest(for: id)
            // A custom action is also written as a single-action manifest package; remove it from
            // disk so it does not reload on the next scan. A legacy store-only action has no
            // package (404), which is not an error.
            await removeManifest(actionID: id)
        case .extensionPkg:
            // Uninstall by package identifier, not the action id: a package's command id need not
            // carry the package prefix, and `uninstallExtension` matches on the identifier.
            await uninstall(actionID: ActionIdentity.extensionPackageID(of: action) ?? id)
        case .builtin, .ai:
            break
        }
    }

    @MainActor
    private static func uninstall(actionID id: String) async {
        do {
            try await ExtensionManager.shared.uninstallExtension(actionID: id)
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        } catch {
            Log.extensions.error("Failed to uninstall extension '\(id, privacy: .public)': \(error.localizedDescription)")
            SettingsRouter.shared.notifyError(
                title: String(localized: "Remove Failed"),
                message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
            )
        }
    }

    @MainActor
    private static func removeManifest(actionID id: String) async {
        do {
            try await ExtensionManager.shared.uninstallExtension(actionID: id)
            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
        } catch {
            let nsError = error as NSError
            if nsError.domain == "ExtensionManager" && nsError.code == 404 { return }
            Log.extensions.error("Failed to remove custom action on disk '\(id, privacy: .public)': \(error.localizedDescription)")
        }
    }
}
