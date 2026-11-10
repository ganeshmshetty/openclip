import Foundation
import Core

/// Preparation sits at the action boundary so bar, search, hotkey and loading paths agree.
struct RichInputAction: ConfigurableAction, ActionWithRules {
    let base: any Action
    let captureRtf: Bool
    let captureHtml: Bool
    let capture: @MainActor @Sendable (SelectionContext) async throws -> SelectionContext

    var id: String { base.id }
    var title: String { base.title }
    var icon: ActionIcon { base.icon }
    var chrome: ActionChrome { base.chrome }
    var actionOptions: [ExtensionOption] { base.actionOptions }
    var delivery: ActionDelivery? { base.delivery }
    var keywords: [String] { base.keywords }
    var preferenceIconName: String { (base as? any ConfigurableAction)?.preferenceIconName ?? "puzzlepiece.extension" }
    var rules: ExtensionActionRules? { (base as? any ActionWithRules)?.rules }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { base.isEnabled(for: context) }
    @MainActor func matchInfo(for context: ActionContext) -> ActionMatchInfo? { base.matchInfo(for: context) }

    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult {
        let needsCapture = (captureRtf && context.selection.rtf == nil) || (captureHtml && context.selection.html == nil)
        guard needsCapture, context.selection.source == .selection else { return try await base.perform(context) }
        let selection = try await capture(context.selection)
        try Task.checkCancellation()
        let enriched = ActionContext(selection: selection, modifiers: context.modifiers,
                                     isSecondaryClick: context.isSecondaryClick, match: context.match,
                                     pasteTargetAvailable: context.pasteTargetAvailable,
                                     visibilityMemo: context.visibilityMemo)
        return try await base.perform(enriched)
    }
}
