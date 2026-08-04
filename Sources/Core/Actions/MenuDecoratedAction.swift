// MenuDecoratedAction.swift
// OpenClip
//
// Pure Core wrapper that stamps optional sub-menu behavior — a relevance regex and a preview
// template — onto an existing action. It decoratively conforms the wrapped action to
// RelevanceProviding and PreviewProviding without changing its identity: id/title/icon/chrome,
// enablement, and perform are all forwarded to the base action, so registry sorting, disabling,
// and customization that key off the action ID are unaffected. The factory wraps extension
// actions that declare menuRelevance / menuPreview; non-declaring actions stay plain.
import Foundation

public struct MenuDecoratedAction: Action, RelevanceProviding, PreviewProviding {
    public let base: any Action
    public let menuRelevanceRegex: String?
    public let menuPreviewTemplate: String?

    public init(
        base: any Action,
        menuRelevanceRegex: String? = nil,
        menuPreviewTemplate: String? = nil
    ) {
        self.base = base
        self.menuRelevanceRegex = menuRelevanceRegex
        self.menuPreviewTemplate = menuPreviewTemplate
    }

    // MARK: - Action (forwarded to base)

    public var id: String { base.id }
    public var title: String { base.title }
    public var icon: ActionIcon { base.icon }
    public var isFormatting: Bool { base.isFormatting }
    public var chrome: ActionChrome { base.chrome }
    public var actionOptions: [ExtensionOption] { base.actionOptions }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        base.isEnabled(for: context)
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        base.matchInfo(for: context)
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        try await base.perform(context)
    }

    // MARK: - RelevanceProviding

    /// Relevant unless a `menuRelevanceRegex` is present and the trimmed selection doesn't match.
    /// A malformed regex is treated as relevant (defensive, mirroring ActionVisibility), so a bad
    /// author pattern never hides a sub-action.
    public func isRelevant(for text: String) -> Bool {
        guard let regex = menuRelevanceRegex, !regex.isEmpty else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let pattern = try? NSRegularExpression(
                  pattern: regex,
                  options: [.dotMatchesLineSeparators, .caseInsensitive]
              ) else {
            return true
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return pattern.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    // MARK: - PreviewProviding

    /// Renders `menuPreviewTemplate` against the selection's context; nil when no template.
    @MainActor
    public func previewLine(for context: ActionContext) async -> String? {
        guard let template = menuPreviewTemplate else { return nil }
        return TextPlaceholderEngine.replacePlaceholders(in: template, context: context, urlEncode: false)
    }
}