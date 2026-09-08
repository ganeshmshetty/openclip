// SelectionMonitoring.swift
// OpenClip
//
// Defines the protocol interface for monitoring system-wide text selection events.
import Foundation

public protocol SelectionMonitoring: AnyObject, Sendable {
    @MainActor var onSelection: ((SelectionContext, Bool?) -> Void)? { get set }
    @MainActor var latestSelection: (context: SelectionContext, canPaste: Bool?)? { get }
    @MainActor func currentSelection(for bundleID: String?) async -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func synchronousSelection(for bundleID: String?) -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func clearSelection()
    @MainActor func start()
    @MainActor func stop()
}

extension SelectionMonitoring {
    @MainActor
    public func synchronousSelection(for bundleID: String?) -> (context: SelectionContext, canPaste: Bool?)? {
        guard let latest = latestSelection,
              let targetBundle = bundleID,
              latest.context.sourceApp.bundleIdentifier == targetBundle else {
            return nil
        }
        guard Date().timeIntervalSince(latest.context.timestamp) <= Constants.selectionMaxAge else {
            return nil
        }
        return latest
    }
}
