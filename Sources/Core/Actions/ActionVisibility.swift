// ActionVisibility.swift
// OpenClip
//
// The shared visibility evaluator for extension actions. Pure: no UserDefaults, no AppKit, no
// Keychain. Resolves declarative requirements in a fixed order (selection, app allow/deny,
// native content, regex/negated) and, when enabled, builds the ActionMatchInfo that
// perform-time placeholders and shell env vars consume.
import Foundation

public enum ActionVisibility {
    /// Pure function — no UserDefaults, no AppKit, no Keychain reads.
    ///
    /// Evaluation order (per plan §3):
    /// 1. Input requirement: optional, nonblank text, live selection, or editable selection.
    /// 2. Required paste destination, when requested.
    /// 3. App allow/deny list vs `context.selection.sourceApp.bundleIdentifier`.
    /// 4. Native content: any requested type must have at least one detected item.
    /// 5. Regex match / negated match, retaining capture groups for execution.
    /// Legacy malformed regexes fail open only for the regex gate; content requirements still apply.
    public static func isEnabled(
        requirements: ActionRequirements?,
        legacyRegex: String?,
        context: ActionContext
    ) -> (enabled: Bool, match: ActionMatchInfo) {
        let text = context.selection.text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBundleID = context.selection.sourceApp.bundleIdentifier
        let noMatch = ActionMatchInfo(text: text, matchedText: text, captures: [], sourceBundleID: sourceBundleID)

        // 1. Input and destination requirements are independent. Unknown capability evidence only
        // fails closed when the action explicitly requires that capability.
        let inputRequirement = requirements?.input ?? .text
        let hasText = !trimmed.isEmpty
        let isLiveSelection = context.selection.source == .selection
        let inputSatisfied: Bool
        switch inputRequirement {
        case .optional:
            inputSatisfied = true
        case .text:
            inputSatisfied = hasText
        case .liveSelection:
            inputSatisfied = hasText && isLiveSelection
        case .editableSelection:
            inputSatisfied = hasText && isLiveSelection && context.selection.isEditable == true
        }
        if !inputSatisfied {
            return (false, noMatch)
        }
        if requirements?.requiresPasteTarget == true && context.pasteTargetAvailable != true {
            return (false, noMatch)
        }

        // 3. App allow/deny list vs the source app bundle identifier.
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

        // Detection is cached on the immutable selection snapshot and reused by execution.
        let requested = requirements?.content ?? []
        let detected = context.selection.detectedContent(for: requested)
        let contentMatch = ActionMatchInfo(text: text, matchedText: text, captures: [],
                                          sourceBundleID: sourceBundleID, detected: detected)
        if requirements?.content != nil && !requested.contains(where: detected.hasItems) {
            return (false, contentMatch)
        }

        // Legacy regex matching also supplies captures to the runtime.
        let pattern = requirements?.regex ?? legacyRegex
        var matched = contentMatch
        var regexEnabled: Bool? = nil
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
                    matched = ActionMatchInfo(text: text, matchedText: matchedText, captures: captures, sourceBundleID: sourceBundleID, detected: detected)
                    regexEnabled = !(requirements?.regexNegated == true)
                } else {
                    regexEnabled = requirements?.regexNegated == true
                }
            } catch {
                // Preserve the legacy regex behavior after all other requirements have passed.
                Log.coordinator.debug("Malformed enablement regex treated as non-matching: \(error.localizedDescription)")
                return (true, contentMatch)
            }
        }
        if regexEnabled == false {
            return (false, matched)
        }

        return (true, matched)
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
        let resolved = Dictionary(options.map { ($0.identifier, optionStore.stringValue(actionID: actionID, option: $0)) }, uniquingKeysWith: { _, latest in latest })
        return missingRequiredOptions(requirements: requirements, resolvedOptions: resolved)
    }
}
