// MacTextRetriever.swift
// OpenClip
//
// TextRetrieving facade over the selection-retrieval coordinator. All retrieval logic (gate, mode
// resolution, settle-retry, strategies) now lives in SelectionRetrievalCoordinator; this type
// exists so existing `TextRetrieving` call sites and tests keep a stable seam.
import Core

// MARK: - MacTextRetriever

@MainActor
internal final class MacTextRetriever: TextRetrieving {
    private let coordinator: SelectionRetrievalCoordinator

    internal init(coordinator: SelectionRetrievalCoordinator = SelectionRetrievalCoordinator()) {
        self.coordinator = coordinator
    }

    // MARK: - TextRetrieving

    internal func retrieveTextResult(for app: AppIdentity, policy: AppPolicyContext) async -> TextResult? {
        await coordinator.retrieve(
            for: app,
            policy: policy,
            cursor: CursorClassifier.current
        )
    }
}