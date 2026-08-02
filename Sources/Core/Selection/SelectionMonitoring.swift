// SelectionMonitoring.swift
// OpenClip
//
// Defines the protocol interface for monitoring system-wide text selection events.
public protocol SelectionMonitoring: Sendable {
    @MainActor var onSelection: ((SelectionContext) -> Void)? { get set }
    @MainActor func start()
    @MainActor func stop()
}
