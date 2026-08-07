// ActionVisibility.swift
// OpenClip
//
// The shared visibility evaluator for extension actions. Pure: no UserDefaults, no AppKit, no
// Keychain. Resolves declarative requirements in a fixed order (selection, app allow/deny,
// regex/negated) and, when enabled, builds the ActionMatchInfo that perform-time placeholders
// and shell env vars consume.
import Foundation

public enum ActionVisibility {
    /// Pure function — no UserDefaults, no AppKit, no Keychain reads.
    ///
    /// Evaluation order (per plan §3):
    /// 1. `requiresSelection` (default `true` for extension actions) — empty text disables,
    ///    except actions that explicitly set `requiresSelection: false`.
    /// 2. App allow/deny list vs `context.selection.sourceApp.bundleIdentifier`.
    /// 3. Regex match / negated match; on success build `ActionMatchInfo`.
    ///
    /// A malformed regex enables the action (defensive stance matching legacy URL behavior,
    /// which returned `true` on a regex compile failure), so a bad manifest never hides an action.
    public static func isEnabled(
        requirements: ActionRequirements?,
        legacyRegex: String?,
        context: ActionContext
    ) -> (enabled: Bool, match: ActionMatchInfo) {
        let text = context.selection.text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBundleID = context.selection.sourceApp.bundleIdentifier
        let noMatch = ActionMatchInfo(text: text, matchedText: text, captures: [], sourceBundleID: sourceBundleID)

        // 1. requiresSelection (default true for extension actions).
        let requiresSelection = requirements?.requiresSelection ?? true
        if requiresSelection && trimmed.isEmpty {
            return (false, noMatch)
        }

        // 2. App allow/deny list vs the source app bundle identifier.
        if let apps = requirements?.apps, !apps.isEmpty {
            switch requirements?.appsMode ?? .allow {
            case .allow:
                guard let sourceBundleID, apps.contains(sourceBundleID) else {
                    return (false, noMatch)
                }
            case .deny:
                if let sourceBundleID, apps.contains(sourceBundleID) {
                    return (false, noMatch)
                }
            }
        }

        // 3. Regex match / negated match.
        let pattern = requirements?.regex ?? legacyRegex
        if let pattern, !pattern.isEmpty {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let result = regex.firstMatch(in: trimmed, options: [], range: range) {
                    let matchedText = Range(result.range, in: trimmed).map { String(trimmed[$0]) } ?? trimmed
                    var captures: [String] = []
                    if regex.numberOfCaptureGroups > 0 {
                        for group in 1...regex.numberOfCaptureGroups {
                            let groupRange = result.range(at: group)
                            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: trimmed) {
                                captures.append(String(trimmed[swiftRange]))
                            } else {
                                captures.append("")
                            }
                        }
                    }
                    let match = ActionMatchInfo(text: text, matchedText: matchedText, captures: captures, sourceBundleID: sourceBundleID)
                    if requirements?.regexNegated == true {
                        return (false, match)
                    }
                    return (true, match)
                }
                // No regex match: enabled when negated, disabled otherwise.
                if requirements?.regexNegated == true {
                    return (true, noMatch)
                }
                return (false, noMatch)
            } catch {
                // Defensive: a malformed regex must not hide an action (legacy URL behavior).
                Log.coordinator.debug("Malformed enablement regex treated as non-matching: \(error.localizedDescription)")
                return (true, noMatch)
            }
        }

        return (true, noMatch)
    }

    /// Returns the identifiers of required options whose resolved value is empty. Pure helper —
    /// never called from `isEnabled`/`evaluate` (Gotcha 4: N synchronous Keychain reads per popup
    /// resolution). Evaluated at perform time: Phase 7's `JavaScriptAction.perform` short-circuits
    /// to `.openConfiguration` when this returns non-empty.
    public static func missingRequiredOptions(
        requirements: ActionRequirements?,
        resolvedOptions: [String: String]
    ) -> [String] {
        guard let requiredOptions = requirements?.requiredOptions, !requiredOptions.isEmpty else { return [] }
        return requiredOptions.filter { optionID in
            let value = resolvedOptions[optionID] ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Resolves every option value through the given store, then delegates to the pure
    /// `missingRequiredOptions(requirements:resolvedOptions:)`. Called at perform time (Phase 7)
    /// before any script runs; a non-empty result means the action cannot run and should open its
    /// configuration instead.
    public static func missingRequiredOptions(
        requirements: ActionRequirements?,
        options: [ExtensionOption],
        optionStore: any ActionOptionReading,
        actionID: String
    ) -> [String] {
        let resolved = Dictionary(uniqueKeysWithValues: options.map { ($0.identifier, optionStore.stringValue(actionID: actionID, option: $0)) })
        return missingRequiredOptions(requirements: requirements, resolvedOptions: resolved)
    }
}
