// ContextualActionClassifier.swift
// OpenClip
//
// Identifies actions that activate on specific content (regex patterns, math, URLs, dates, paths)
// and resolves their human-readable trigger descriptions for Contextual Actions.
import Foundation

public enum ContextualActionClassifier {
    /// Unwraps any decorator actions (MenuDecoratedAction, KeywordDecoratedAction, DeliveryDecoratedAction)
    /// to get the underlying concrete Action instance.
    public static func unwrap(_ action: any Action) -> any Action {
        var current = action
        while true {
            if let decorated = current as? MenuDecoratedAction {
                current = decorated.base
            } else if let decorated = current as? KeywordDecoratedAction {
                current = decorated.base
            } else if let decorated = current as? DeliveryDecoratedAction {
                current = decorated.base
            } else {
                return current
            }
        }
    }

    /// True when the action specifies specialized content/pattern detection.
    public static func isContextual(_ action: any Action) -> Bool {
        triggerDescription(for: action) != nil
    }

    /// User-facing description of what triggers this action (e.g. "Math expressions", "Web links and URLs").
    public static func triggerDescription(for action: any Action) -> String? {
        if let decorated = action as? MenuDecoratedAction,
           let pattern = decorated.menuRelevanceRegex, !pattern.isEmpty {
            return String(localized: "Matches pattern: \(pattern)")
        }

        let underlying = unwrap(action)

        switch underlying.id.lowercased() {
        case "builtin.calculate":
            return String(localized: "Math expressions")
        case "builtin.openurl", "builtin.open_url":
            return String(localized: "Web links and URLs")
        case "builtin.calendar":
            return String(localized: "Dates and calendar events")
        case "builtin.reveal_in_finder", "builtin.revealinfinder":
            return String(localized: "File and folder paths")
        case "builtin.define":
            return String(localized: "Dictionary definitions")
        default:
            break
        }

        // A URL-template action is contextual only when it declares a pattern. Without one it runs
        // on any selection (e.g. "Search Google for {query}") and must not jump ahead of the
        // user's saved action order just because URL templates default to a `.url` badge.
        if let template = underlying as? URLTemplateAction,
           let pattern = template.regexPattern, !pattern.isEmpty {
            return String(localized: "Matches pattern: \(pattern)")
        }

        if let custom = underlying as? CustomAction,
           case .openURL = custom.type,
           let pattern = custom.rules?.requirements?.regex ?? custom.rules?.legacyRegex, !pattern.isEmpty {
            return String(localized: "Matches pattern: \(pattern)")
        }

        if let withRules = underlying as? any ActionWithRules,
           let pattern = withRules.rules?.requirements?.regex ?? withRules.rules?.legacyRegex,
           !pattern.isEmpty {
            return String(localized: "Matches pattern: \(pattern)")
        }

        return nil
    }
}

public extension Action {
    /// True when the action targets specific text patterns rather than generic selection.
    var isContextual: Bool {
        ContextualActionClassifier.isContextual(self)
    }

    /// User-facing description of the contextual trigger requirement.
    var contextualTriggerDescription: String? {
        ContextualActionClassifier.triggerDescription(for: self)
    }
}
