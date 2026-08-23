// Notification.Name+OpenClip.swift
// OpenClip
//
// Central registry of OpenClip-specific Notification.Name values, replacing scattered inline string
// literals so presentation and composition code share one source of truth.
import Foundation

extension Notification.Name {
    /// Posted when an action requests its configuration UI. The popup hides first
    /// (`.openConfiguration` dismisses the popup); the payload `ConfigurationRequest` travels in
    /// `userInfo["request"]`. StatusBarController/Preferences observes this, finds the action by id
    /// in `ActionCoordinator.shared.actions`, and presents its `EditActionSheet`.
    static let openClipOpenActionConfiguration = Notification.Name("OpenClipOpenActionConfiguration")
}
