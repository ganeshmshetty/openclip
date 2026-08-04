// ActionFactory.swift
// OpenClip
//
// Defines the factory protocol for creating action instances from extension manifests and snippet metadata through the Birth Door seam.
import Foundation

public protocol ActionFactory: Sendable {
    func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> (any Action)?
}
