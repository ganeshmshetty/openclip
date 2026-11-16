// SelectionMonitoring.swift
// OpenClip
//
// Defines the protocol interface for monitoring system-wide text selection events.
import Foundation

public protocol SelectionMonitoring: AnyObject, Sendable {
    @MainActor var onSelection: ((SelectionContext, Bool?) -> Void)? { get set }
    @MainActor var selectionGeneration: UInt64? { get }
    @MainActor var latestSelection: (context: SelectionContext, canPaste: Bool?)? { get }
    @MainActor func currentSelection(for bundleID: String?) async -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func synchronousSelection(for bundleID: String?) -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func currentSelection(for app: AppIdentity) async -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func synchronousSelection(for app: AppIdentity) -> (context: SelectionContext, canPaste: Bool?)?
    @MainActor func clearSelection()
    @MainActor func cancelPendingSelection()
    @MainActor func start()
    @MainActor func stop()
}

extension SelectionMonitoring {
    @MainActor public func cancelPendingSelection() {}
    @MainActor public var selectionGeneration: UInt64? { nil }
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

    @MainActor
    public func synchronousSelection(for app: AppIdentity) -> (context: SelectionContext, canPaste: Bool?)? {
        guard let latest = latestSelection else { return nil }
        if let targetPID = app.processIdentifier, let sourcePID = latest.context.sourceApp.processIdentifier {
            guard targetPID == sourcePID else { return nil }
        }
        guard app.isSameApp(as: latest.context.sourceApp) else { return nil }
        guard Date().timeIntervalSince(latest.context.timestamp) <= Constants.selectionMaxAge else {
            return nil
        }
        return latest
    }

    @MainActor
    public func currentSelection(for app: AppIdentity) async -> (context: SelectionContext, canPaste: Bool?)? {
        return synchronousSelection(for: app)
    }
}
