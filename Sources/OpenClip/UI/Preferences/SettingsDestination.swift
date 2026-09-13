// SettingsDestination.swift
// OpenClip
//
// Where an action's settings live in the Settings window, as a router path. Every surface that
// points at an action — a double-click on the Customize list, a command on an extension's page,
// a name in the Shortcuts table, a configure request from the popup — asks here, so the answer
// is the same everywhere and the sidebar always highlights the page an action belongs to.

import Core

enum SettingsDestination {
    /// True for the user's own actions: the ones created in Settings (Open URL, Text Snippet,
    /// Shell Script), whether they load from the settings store or from the single-action manifest
    /// package the app writes for them.
    static func isCustomAction(_ action: any Action) -> Bool {
        guard action.chrome.rowStyle != .actionGroup else { return false }
        if case .custom = action.chrome.source { return true }
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           InstalledExtensionInfo.isCustomPackage(packageID) {
            return true
        }
        return action is CustomAction
    }

    /// The path that shows `action`'s settings.
    ///
    /// - AI Tools is the AI page; one of its prompts is that prompt's page under AI.
    /// - An extension's group row, or the placeholder the trust gate registers for it, is the
    ///   extension's page; one of its commands is that command's editor under the extension's page.
    /// - A custom group is the group editor under Customize, where groups are made.
    /// - A custom action is its editor under Custom Actions.
    /// - A built-in action has a sidebar row of its own.
    @MainActor
    static func path(for action: any Action) -> [SettingsPage] {
        if action.chrome.launchesAI {
            return [.ai]
        }
        if ActionIdentity.isAIPreset(action) {
            if let preset = AIServiceManager.shared.preset(forActionID: action.id) {
                return [.ai, .aiPreset(id: preset.id)]
            }
            return [.ai]
        }
        if let gated = action as? GatedExtensionAction {
            return [.extensionPackage(id: gated.packageID)]
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           case .extensionPkg = action.chrome.source,
           !InstalledExtensionInfo.isCustomPackage(packageID) {
            if action.chrome.popupBehavior == .showSubActions {
                return [.extensionPackage(id: packageID)]
            }
            if let info = InstalledExtensionInfo.info(for: packageID, in: ActionCoordinator.shared.actions),
               info.commands.count == 1,
               !info.isGroup {
                return [.extensionPackage(id: packageID)]
            }
            return [.extensionPackage(id: packageID), .action(id: action.id)]
        }
        if action.chrome.rowStyle == .actionGroup {
            return [.customize, .action(id: action.id)]
        }
        if isCustomAction(action) {
            return [.customActions, .action(id: action.id)]
        }
        if ActionIdentity.isBuiltin(action) {
            return [.builtinAction(id: action.id)]
        }
        return [.customize, .action(id: action.id)]
    }

    /// The path for a package header row in the Customize list.
    static func path(forPackage packageID: String) -> [SettingsPage] {
        [.extensionPackage(id: packageID)]
    }

    @MainActor
    static func open(_ action: any Action) {
        SettingsRouter.shared.show(path: path(for: action))
    }
}
