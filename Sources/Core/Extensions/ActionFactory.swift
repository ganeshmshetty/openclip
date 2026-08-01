import Foundation

public protocol ActionFactory: Sendable {
    func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL
    ) async -> (any Action)?
}
