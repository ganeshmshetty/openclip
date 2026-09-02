// ExtensionUpdateBatchResult.swift
// OpenClip
//
// Outcome of a batch extension update (updateAll). Pure Core — the app target runs the actual
// per-package updates and feeds them through collect(packageIDs:update:), which isolates the
// success/failure bookkeeping so it can be unit-tested without network or singletons.
import Foundation

public struct ExtensionUpdateBatchResult: Sendable, Equatable {
    public let succeeded: [String]
    /// Package ID → localized error message for every package whose update threw.
    public let failed: [String: String]

    public init(succeeded: [String], failed: [String: String]) {
        self.succeeded = succeeded
        self.failed = failed
    }

    public var total: Int { succeeded.count + failed.count }
    public var hasFailures: Bool { !failed.isEmpty }

    /// Runs `update` for each ID in order, recording successes and the localized description of
    /// any thrown error. One failure never aborts the rest of the batch.
    public static func collect(
        packageIDs: [String],
        update: (String) async throws -> Void
    ) async -> ExtensionUpdateBatchResult {
        var succeeded: [String] = []
        var failed: [String: String] = [:]
        for id in packageIDs {
            do {
                try await update(id)
                succeeded.append(id)
            } catch {
                failed[id] = error.localizedDescription
            }
        }
        return ExtensionUpdateBatchResult(succeeded: succeeded, failed: failed)
    }
}
