// URLTemplateAction.swift
// OpenClip
//
// Implements web search and URL opening actions using parameterized text template strings and
// optional regex matching rules. Enablement and match resolution delegate to the shared
// ActionVisibility evaluator; the legacy `regexPattern` maps into it as the legacyRegex so
// pre-rules URL actions keep filtering identically.
import Foundation

public struct URLTemplateAction: Action, Sendable {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let urlTemplate: String
    public let regexPattern: String?
    public let rules: ExtensionActionRules?
    
    public let chrome: ActionChrome
    
    public init(id: String, title: String, icon: ActionIcon, urlTemplate: String, regexPattern: String? = nil, chrome: ActionChrome? = nil, rules: ExtensionActionRules? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.urlTemplate = urlTemplate
        self.regexPattern = regexPattern
        self.rules = rules
        self.chrome = chrome ?? ActionChrome(badge: .url, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
    }

    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        ActionVisibility.isEnabled(
            requirements: rules?.requirements,
            legacyRegex: rules?.legacyRegex ?? regexPattern,
            context: context
        ).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        ActionVisibility.isEnabled(
            requirements: rules?.requirements,
            legacyRegex: rules?.legacyRegex ?? regexPattern,
            context: context
        ).match
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        // The popup threads the matched context in; direct callers (tests, legacy paths) fall
        // back to a match whose text is the trimmed selection so `{text}`/`{query}` keep their
        // historical trimmed value and the new {matched}/{captureN}/{bundleID} placeholders are
        // no-ops.
        let trimmed = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let performContext: ActionContext
        if let match = context.match {
            performContext = context
        } else {
            performContext = ActionContext(
                selection: context.selection,
                modifiers: context.modifiers,
                match: ActionMatchInfo(text: trimmed, matchedText: trimmed, captures: [], sourceBundleID: context.selection.sourceApp.bundleIdentifier)
            )
        }
        let urlString = TextPlaceholderEngine.replacePlaceholders(in: urlTemplate, context: performContext, urlEncode: true)
        
        if let url = URL(string: urlString) {
            return .openURL(url)
        }
        
        return .none
    }
}
