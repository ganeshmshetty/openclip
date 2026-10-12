import Core
import Combine

/// A time-dependent preview bypasses the generic cross-popup string memoization.
struct InlineActionPreview {
    let label: String
    let result: ActionResult
}

@MainActor
protocol LiveInlineAction: AnyObject, Action {
    var previewChanges: AnyPublisher<Void, Never> { get }
    func preview(for context: ActionContext) -> InlineActionPreview?
    func preparePreview(for context: ActionContext)
}
