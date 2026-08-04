// TransformTextAction.swift
// OpenClip
//
// Implements the builtin text case-conversion sub-actions (uppercase, lowercase, title case,
// camel case) grouped under the Transform Text row. The default-on/off transform policy lives on
// TransformCase.defaultDisabledActionIDs; smart menu relevance lives in
// TransformCase.isRelevant(for:).
import Foundation

public enum TransformCase: String, CaseIterable, Sendable, Identifiable {
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case titleCase = "titleCase"
    case camelCase = "camelCase"

    public var id: String { rawValue }

    /// Transform sub-actions that are enabled by default. Every surviving transform case is on by
    /// default, so `defaultDisabledActionIDs` is empty today; the set is kept as the single source
    /// of the default-on/off policy the registry reads.
    public static let defaultEnabledTransformCases: Set<TransformCase> = [
        .uppercase, .lowercase, .titleCase, .camelCase
    ]

    /// IDs of transform actions disabled by default: every sub-action not in
    /// `defaultEnabledTransformCases` (empty today — all four case conversions are enabled by
    /// default). The transform GROUP row (`builtin.transform`) is NOT in this set — the group is
    /// enabled by default so the sub-menu is the default presentation, and
    /// `ActionRegistry.availableActions` hides sub-actions whenever their group row is disabled.
    /// The registry reads this instead of duplicating the default-on/off policy.
    public static var defaultDisabledActionIDs: [String] {
        allCases
            .filter { !defaultEnabledTransformCases.contains($0) }
            .map { "builtin.transform.\($0.rawValue)" }
    }

    public var displayName: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .camelCase: return "camelCase"
        }
    }

    /// Whether this transform is useful for the given selection. Used to smart-filter the
    /// transform sub-action menu so no-op entries are never shown.
    ///
    /// Policy: a case conversion is relevant only when the selection contains words and the
    /// conversion would actually change the text (already-uppercase text hides UPPERCASE, a
    /// single lowercase word hides camelCase, etc.).
    public func isRelevant(for text: String) -> Bool {
        let hasWords = text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        guard hasWords else { return false }
        return transform(text) != text
    }

    public func transform(_ text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return words(in: text).map { $0.capitalized }.joined(separator: " ")
        case .camelCase:
            let words = words(in: text)
            guard let first = words.first?.lowercased() else { return text }
            let rest = words.dropFirst().map { $0.capitalized }
            return ([first] + rest).joined()
        }
    }

    private func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

public struct TransformSubAction: Action {
    public let transformCase: TransformCase

    public var id: String { "builtin.transform.\(transformCase.rawValue)" }
    public var title: String { transformCase.displayName }
    public var icon: ActionIcon { .symbol("textformat") }

    public init(transformCase: TransformCase) {
        self.transformCase = transformCase
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let transformed = transformCase.transform(context.selection.text)
        return .paste(transformed)
    }
}

public struct TransformTextGroupAction: Action {
    public let id = "builtin.transform"
    public let title = "Transform Text"
    public let icon = ActionIcon.symbol("textformat")
    public let chrome = ActionChrome(badge: .none, rowStyle: .transformGroup, popupBehavior: .showTransformMenu, source: .builtin)

    public init() {}

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .none
    }
}
