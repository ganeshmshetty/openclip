// ActionVisibility.swift
// OpenClip
//
// Shared visibility evaluator for extension actions. Pure: no UserDefaults, AppKit, or Keychain.
import Foundation

public enum ActionVisibility {
    private final class RegexCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: NSRegularExpression] = [:]
        private let limit = 256

        func regex(for pattern: String) -> NSRegularExpression? {
            lock.lock()
            if let cached = entries[pattern] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            guard let compiled = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) else {
                return nil
            }
            lock.lock()
            // Manifest reloads can introduce new patterns; a full wipe keeps the cache bounded without
            // tracking per-pattern recency on the popup path.
            if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
            entries[pattern] = compiled
            lock.unlock()
            return compiled
        }
    }

    private static let regexCache = RegexCache()

    /// Order: input, paste target, app allow/deny, native content, then regex. The match info built here
    /// carries captures and detected content to execution. A malformed regex fails open for the regex
    /// gate only; content requirements still apply.
    public static func isEnabled(
        requirements: ActionRequirements?,
        legacyRegex: String?,
        context: ActionContext
    ) -> (enabled: Bool, match: ActionMatchInfo) {
        let text = context.selection.text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBundleID = context.selection.sourceApp.bundleIdentifier
        let noMatch = ActionMatchInfo(text: text, matchedText: text, captures: [], sourceBundleID: sourceBundleID)

        // Declared requirements fail closed: unknown evidence does not satisfy them.
        if !ActionEligibility.isSatisfied(
            requirements: requirements,
            selection: context.selection,
            capabilities: context.capabilities
        ) {
            return (false, noMatch)
        }

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

        let pattern = requirements?.regex ?? legacyRegex
        var matched = contentMatch
        var regexEnabled: Bool? = nil
        if let pattern, !pattern.isEmpty {
            do {
                guard let regex = Self.regexCache.regex(for: pattern) else {
                    throw NSError(domain: "ActionVisibility", code: 1, userInfo: [NSLocalizedDescriptionKey: "Malformed regular expression"])
                }
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
                // Malformed regex must not hide an action (legacy URL behavior).
                Log.coordinator.debug("Malformed enablement regex treated as non-matching: \(error.localizedDescription)")
                return (true, contentMatch)
            }
        }
        if regexEnabled == false {
            return (false, matched)
        }

        return (true, matched)
    }

    /// IDs of required options whose resolved value is empty. Kept out of `isEnabled` to avoid
    /// per-popup Keychain reads; checked at perform time.
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

    /// Resolves option values through `optionStore`, then delegates to the pure overload.
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
