// ConfigurationRequest.swift
// OpenClip
//
// Pure Core value type describing a request from an action to open its configuration UI. Carried in
// the `openClipOpenActionConfiguration` notification's userInfo; Preferences finds the action by id
// in `ActionCoordinator.shared.actions` (data-driven — never by string switching) and presents its
// `EditActionSheet`.
import Foundation

public struct ConfigurationRequest: Sendable, Equatable {
    /// The id of the action to configure (matches `Action.id`).
    public var actionID: String
    /// Optional human-readable reason shown to the user (Phase 7 surfaces this as a banner).
    public var reason: String?
    /// Option ids that are missing/invalid; Phase 7 highlights them in the sheet.
    public var missingOptionIDs: [String]

    public init(actionID: String, reason: String? = nil, missingOptionIDs: [String] = []) {
        self.actionID = actionID
        self.reason = reason
        self.missingOptionIDs = missingOptionIDs
    }
}