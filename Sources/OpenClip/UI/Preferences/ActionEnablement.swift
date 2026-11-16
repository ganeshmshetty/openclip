// ActionEnablement.swift
// OpenClip
//
// The one rule for an action's enable switch, shared by the Actions list and the extension pages.
// Disabled parent groups block child switches without changing their saved choices.
// Turning a standalone package action on re-enables its package; AI presets keep their state in AIServiceManager;
// a gated (untrusted) extension can only be turned on, which is what re-trusts it.

import SwiftUI
import Core

enum ActionEnablement {
    @MainActor
    static func binding(
        for action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        coordinator: ActionCoordinator = .shared
    ) -> Binding<Bool> {
        let stored = storedBinding(
            for: action, disabledActionIDs: disabledActionIDs,
            disabledPackages: disabledPackages, coordinator: coordinator
        )
        return Binding(
            get: {
                !coordinator.isDisabledByParentGroup(
                    action, disabledActionIDs: disabledActionIDs.wrappedValue,
                    disabledPackages: disabledPackages.wrappedValue
                ) && stored.wrappedValue
            },
            set: { enabled in
                guard !coordinator.isDisabledByParentGroup(
                    action, disabledActionIDs: disabledActionIDs.wrappedValue,
                    disabledPackages: disabledPackages.wrappedValue
                ) else { return }
                stored.wrappedValue = enabled
            }
        )
    }

    @MainActor
    private static func storedBinding(
        for action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        coordinator: ActionCoordinator
    ) -> Binding<Bool> {
        if ActionIdentity.isAIPreset(action) {
            return Binding(
                get: { AIServiceManager.shared.preset(forActionID: action.id)?.isEnabled ?? false },
                set: { enabled in
                    guard var preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
                    preset.isEnabled = enabled
                    AIServiceManager.shared.updatePreset(preset)
                }
            )
        }
        if let gated = action as? GatedExtensionAction {
            return Binding(
                get: { false },
                set: { enabled in
                    guard enabled else { return }
                    disabledActionIDs.wrappedValue.remove(action.id)
                    disabledPackages.wrappedValue.remove(gated.packageID)
                    Task {
                        await ExtensionManager.shared.enablePackage(packageID: gated.packageID)
                        NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                    }
                }
            )
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action) {
            return Binding(
                get: {
                    !disabledActionIDs.wrappedValue.contains(action.id)
                        && !disabledPackages.wrappedValue.contains(packageID)
                },
                set: { enabled in
                    if enabled {
                        disabledActionIDs.wrappedValue.remove(action.id)
                        if action.chrome.popupBehavior == .showSubActions {
                            if disabledPackages.wrappedValue.contains(packageID) {
                                disabledPackages.wrappedValue.remove(packageID)
                                let nonGroupSiblings = coordinator.actions.filter {
                                    ActionIdentity.extensionPackageID(of: $0) == packageID
                                    && $0.id != action.id
                                    && !$0.id.hasPrefix(action.id + ".")
                                    && $0.chrome.popupBehavior != .showSubActions
                                }
                                for sib in nonGroupSiblings {
                                    disabledActionIDs.wrappedValue.insert(sib.id)
                                }
                            }
                        } else {
                            let parent = coordinator.actions.first(where: {
                                ActionIdentity.extensionPackageID(of: $0) == packageID
                                && $0.chrome.popupBehavior == .showSubActions
                                && action.id != $0.id
                                && action.id.hasPrefix($0.id + ".")
                            })
                            if disabledPackages.wrappedValue.contains(packageID) {
                                disabledPackages.wrappedValue.remove(packageID)
                                // Keep other executable actions in this package disabled so only this action is enabled,
                                // but never disable the group container row itself.
                                let siblingIDs = coordinator.actions
                                    .filter {
                                        ActionIdentity.extensionPackageID(of: $0) == packageID
                                        && $0.id != action.id
                                        && $0.id != parent?.id
                                        && $0.chrome.popupBehavior != .showSubActions
                                    }
                                    .map(\.id)
                                for sibID in siblingIDs {
                                    disabledActionIDs.wrappedValue.insert(sibID)
                                }
                            }
                        }
                    } else {
                        disabledActionIDs.wrappedValue.insert(action.id)
                    }
                }
            )
        }
        return Binding(
            get: { !disabledActionIDs.wrappedValue.contains(action.id) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.wrappedValue.remove(action.id)
                } else {
                    disabledActionIDs.wrappedValue.insert(action.id)
                }
            }
        )
    }

    /// The switch for a whole package: off while the package is disabled, gated, or all its commands are off.
    /// Turning it on clears disabled states and trusts the package if gated.
    @MainActor
    static func packageBinding(
        packageID: String,
        gatedReason: ExtensionGateReason?,
        disabledPackages: Binding<Set<String>>,
        disabledActionIDs: Binding<Set<String>>? = nil,
        coordinator: ActionCoordinator = .shared
    ) -> Binding<Bool> {
        Binding(
            get: {
                if gatedReason != nil { return false }
                if disabledPackages.wrappedValue.contains(packageID) { return false }
                if let disabledActionIDs = disabledActionIDs?.wrappedValue {
                    let actions = coordinator.actions.filter { ActionIdentity.extensionPackageID(of: $0) == packageID }
                    if !actions.isEmpty && actions.allSatisfy({ disabledActionIDs.contains($0.id) }) {
                        return false
                    }
                }
                return true
            },
            set: { enabled in
                if enabled {
                    disabledPackages.wrappedValue.remove(packageID)
                    if let disabledActionIDs {
                        let actionIDs = coordinator.actions
                            .filter { ActionIdentity.extensionPackageID(of: $0) == packageID }
                            .map(\.id)
                        for id in actionIDs {
                            disabledActionIDs.wrappedValue.remove(id)
                        }
                    }
                    if gatedReason != nil {
                        Task {
                            await ExtensionManager.shared.enablePackage(packageID: packageID)
                            NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                        }
                    }
                } else {
                    disabledPackages.wrappedValue.insert(packageID)
                }
            }
        )
    }
}
