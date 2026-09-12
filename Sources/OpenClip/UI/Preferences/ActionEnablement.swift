// ActionEnablement.swift
// OpenClip
//
// The one rule for an action's enable switch, shared by the Actions list and the extension pages.
// An action is off when its own id is disabled or its package is; turning a package's action back
// on re-enables the package; the AI launcher and AI presets keep their state in AIServiceManager;
// a gated (untrusted) extension can only be turned on, which is what re-trusts it.

import SwiftUI
import Core

enum ActionEnablement {
    @MainActor
    static func binding(
        for action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>
    ) -> Binding<Bool> {
        if action.chrome.launchesAI {
            return Binding(
                get: { AIServiceManager.shared.isAIEnabled },
                set: { AIServiceManager.shared.isAIEnabled = $0 }
            )
        }
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
                        if disabledPackages.wrappedValue.contains(packageID) {
                            disabledPackages.wrappedValue.remove(packageID)
                            Task {
                                await ExtensionManager.shared.enablePackage(packageID: packageID)
                                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
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

    /// The switch for a whole package: off while the package is disabled or gated; turning it on
    /// re-trusts and reloads the package, turning it off revokes it.
    @MainActor
    static func packageBinding(
        packageID: String,
        gatedReason: ExtensionGateReason?,
        disabledPackages: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { gatedReason == nil && !disabledPackages.wrappedValue.contains(packageID) },
            set: { enabled in
                if enabled {
                    disabledPackages.wrappedValue.remove(packageID)
                    Task {
                        await ExtensionManager.shared.enablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                    }
                } else {
                    disabledPackages.wrappedValue.insert(packageID)
                    Task {
                        await ExtensionManager.shared.disablePackage(packageID: packageID)
                        NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                    }
                }
            }
        )
    }
}
