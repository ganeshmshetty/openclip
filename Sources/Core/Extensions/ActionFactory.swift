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

    /// Creates every registry entry for one manifest action. Groups flatten into a group row plus
    /// one entry per sub-action; every other kind delegates to `createAction`. Conformers that
    /// don't care about groups get the default single-action behavior.
    func createActions(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> [any Action]
}

public extension ActionFactory {
    func createActions(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> [any Action] {
        guard let action = await createAction(metadata: metadata, manifest: manifest, directoryURL: directoryURL, index: index) else { return [] }
        return [action]
    }
}
