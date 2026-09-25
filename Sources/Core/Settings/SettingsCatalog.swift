// SettingsCatalog.swift
// OpenClip
//
// The list of known settings, in erased form, so code can walk every setting without knowing its
// type (snapshot, export/import, diagnostics). Keeping the list here — referencing the existing
// `SettingKey` declarations — means the "what settings exist" answer lives in one place.
//
// Dynamic per-action keys (`action.<id>.option.<id>`) are intentionally not enumerated here; they
// are scoped to their action and are not part of the global settings snapshot.
import Foundation

public enum SettingsCatalog {
    /// Every setting declared in Core.
    public static var coreKeys: [AnySettingKey] {
        [
            // Action ordering / enablement
            SettingKey.actionOrder.erased,
            SettingKey.disabledActionIDs.erased,
            SettingKey.disabledPackages.erased,
            SettingKey.disabledContextualActionIDs.erased,
            SettingKey.contextualActionsEnabled.erased,
            SettingKey.actionUsageRecency.erased,
            SettingKey.extensionGroupMemberOrder.erased,
            SettingKey.actionAliases.erased,

            // Extensions
            SettingKey.extensionTrust.erased,
            SettingKey.extensionTrustHashes.erased,
            SettingKey.extensionSources.erased,
            SettingKey.extensionTrustMigrated.erased,

            // App / behavior toggles
            SettingKey.isAppEnabled.erased,
            SettingKey.isAIEnabled.erased,
            SettingKey.isMouseHoldEnabled.erased,
            SettingKey.hasCompletedOnboarding.erased,
            SettingKey.hasDismissedPostOnboardingCoachMark.erased,
            SettingKey.startAtLogin.erased,
            SettingKey.completionCopyToClipboard.erased,

            // Updates
            SettingKey.automaticallyChecksForUpdates.erased,
            SettingKey.automaticallyDownloadsUpdates.erased,
            SettingKey.notifyOnUpdate.erased,
            SettingKey.updateChannel.erased,

            // Popup presentation
            SettingKey.popupPageSize.erased,
            SettingKey.popupBarWidth.erased,
            SettingKey.popupScale.erased,
            SettingKey.popupTheme.erased,
            SettingKey.popupThemeColor.erased,
            SettingKey.popupAlignment.erased,
            SettingKey.popupVerticalPosition.erased,

            // Gesture / lifecycle
            SettingKey.mouseHoldDuration.erased,
            SettingKey.pauseUntilTimestamp.erased,
            SettingKey.lastRunVersion.erased,
            SettingKey.lastRunBuild.erased,

            // Builtin action config
            SettingKey.calendarProvider.erased,
            SettingKey.searchURL.erased,
            SettingKey.fileSaveLocation.erased,

            // Structured blobs
            SettingKey.actionCustomizations.erased,
            SettingKey.actionGroups.erased,
            SettingKey.customActions.erased
        ]
    }
}
