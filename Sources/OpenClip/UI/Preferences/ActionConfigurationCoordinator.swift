// ActionConfigurationCoordinator.swift
// OpenClip
//
// Holds the most recent ConfigurationRequest from the popup so Preferences can present the matching
// EditActionSheet even when the preferences window wasn't already open when the request arrived.
// StatusBarController's notification observer stores the request here; PreferencesView observes it.
import Foundation
import Combine
import Core

@MainActor
public final class ActionConfigurationCoordinator: ObservableObject {
    public static let shared = ActionConfigurationCoordinator()

    /// The request to present next (cleared once Preferences consumes it).
    @Published public var pendingRequest: ConfigurationRequest?

    private init() {}
}
