// TopLevelActionItem.swift
// OpenClip
//
// Pure Core presentation model and resolver for top-level actions and groups.
// Formats actions for top-level menus (e.g. status bar item) omitting nested sub-actions and AI presets.
import Foundation

/// Pure presentation model for a top-level action or group in the menu bar.
public struct TopLevelActionItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let isGroup: Bool
    public let isAI: Bool
    public let isEnabled: Bool

    public init(id: String, title: String, icon: ActionIcon, isGroup: Bool, isAI: Bool, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isGroup = isGroup
        self.isAI = isAI
        self.isEnabled = isEnabled
    }
}

/// Resolves top-level actions and groups from an action catalog.
public enum TopLevelActionResolver {
    /// Extracts top-level actions and groups in sorted order, omitting AI presets and sub-actions
    /// of custom groups or extension packages.
    public static func resolveTopLevelItems(
        from actions: [any Action],
        customGroupMemberIDs: Set<String>,
        disabledActionIDs: Set<String>,
        isAIEnabled: Bool,
        presentationProvider: ((any Action) -> ActionPresentationModel)? = nil
    ) -> [TopLevelActionItem] {
        let groupPackages = Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions }
                .compactMap { ActionIdentity.extensionPackageID(of: $0) }
        )

        var items: [TopLevelActionItem] = []
        for action in actions {
            // Omit AI presets
            if ActionIdentity.isAIPreset(action) {
                continue
            }
            let presentation = presentationProvider?(action) ?? ActionPresentationModel(title: action.title, icon: action.icon)
            // Groups / Folders
            if action.chrome.popupBehavior == .showSubActions {
                let isEnabled = !disabledActionIDs.contains(action.id)
                items.append(TopLevelActionItem(
                    id: action.id,
                    title: presentation.title,
                    icon: presentation.icon,
                    isGroup: true,
                    isAI: false,
                    isEnabled: isEnabled
                ))
                continue
            }
            // Omit custom group members
            if customGroupMemberIDs.contains(action.id) {
                continue
            }
            // Omit extension package group sub-actions
            if let pkg = ActionIdentity.extensionPackageID(of: action), groupPackages.contains(pkg) {
                continue
            }
            // Standalone action
            let isAI = action.chrome.launchesAI
            let isEnabled = isAI ? isAIEnabled : !disabledActionIDs.contains(action.id)
            items.append(TopLevelActionItem(
                id: action.id,
                title: presentation.title,
                icon: presentation.icon,
                isGroup: false,
                isAI: isAI,
                isEnabled: isEnabled
            ))
        }
        return items
    }
}
