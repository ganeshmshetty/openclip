// RuleEngine.swift
// OpenClip
//
// Evaluates active selection contexts against application rules to determine if OpenClip actions should be enabled or suppressed.
import Foundation
import Combine

public struct RuleEngineConfig: Codable, Sendable {
    public let rules: [AppRule]
}

@MainActor
public final class RuleEngine: ObservableObject, Sendable {
    public static let shared = RuleEngine()
    
    @Published public private(set) var userRules: [AppRule] = []
    
    // The fully expanded rules list used for evaluation
    private var effectiveRules: [AppRule] {
        RuleEngine.expandRules(Self.defaultRules + userRules)
    }
    
    private init() {
    }
    
    public func loadRules(from url: URL) async {
        let logger = Log.settings
        let loadedRules = await Task.detached { () -> [AppRule]? in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let config = try decoder.decode(RuleEngineConfig.self, from: data)
                logger.info("Successfully loaded \(config.rules.count) rules from \(url.lastPathComponent, privacy: .public)")
                return config.rules
            } catch {
                logger.error("Failed to load rules from \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
                return nil
            }
        }.value
        
        if let loadedRules = loadedRules {
            self.userRules = loadedRules
        }
    }
    
    public func saveRules(to url: URL) {
        let config = RuleEngineConfig(rules: userRules)
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: url)
            Log.settings.info("Successfully saved \(self.userRules.count) rules to \(url.lastPathComponent, privacy: .public)")
        } catch {
            Log.settings.error("Failed to save rules to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    public func addOrUpdateRule(_ rule: AppRule, saveURL: URL = Constants.rulesFileURL) {
        // If there's already a rule for this exact bundle identifier set, replace it.
        // Otherwise append. We simplify by matching the first bundle identifier.
        if let firstID = rule.bundleIdentifiers.first,
           let index = userRules.firstIndex(where: { $0.bundleIdentifiers.first == firstID }) {
            userRules[index] = rule
        } else {
            userRules.append(rule)
        }
        saveRules(to: saveURL)
    }
    
    public func removeRule(id: String, saveURL: URL = Constants.rulesFileURL) {
        userRules.removeAll(where: { $0.id == id })
        saveRules(to: saveURL)
    }
    
    private static func expandRules(_ rules: [AppRule]) -> [AppRule] {
        return rules.map { rule in
            var expandedIdentifiers: [String] = []
            for id in rule.bundleIdentifiers {
                if id == ":menu-copy-apps:" {
                    expandedIdentifiers.append(contentsOf: DefaultAppRules.menuCopyApps)
                } else {
                    expandedIdentifiers.append(id)
                }
            }
            return AppRule(
                bundleIdentifiers: expandedIdentifiers,
                useMenuCopy: rule.useMenuCopy,
                denyPaste: rule.denyPaste,
                retrievalMode: rule.retrievalMode,
                gate: rule.gate
            )
        }
    }
    
    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        var context = AppPolicyContext.default
        var explicitRetrievalMode = false

        for rule in effectiveRules {
            if rule.bundleIdentifiers.contains(where: { matchPattern($0, with: bundleIdentifier) }) {
                if rule.retrievalMode != nil {
                    explicitRetrievalMode = true
                }
                context = AppPolicyContext(
                    denyPaste: rule.denyPaste ?? context.denyPaste,
                    useMenuCopy: rule.useMenuCopy ?? context.useMenuCopy,
                    retrievalMode: rule.retrievalMode ?? context.retrievalMode,
                    gate: rule.gate ?? context.gate
                )
            }
        }

        // Legacy alias: a `use-menu-copy: true` rule that never set an explicit retrieval mode
        // resolves to `.menuCopy`, preserving old rule files' behavior. A matching rule that
        // explicitly supplied `retrieval-mode` (even `.axTextControl`) opts out of the conversion.
        if context.useMenuCopy && context.retrievalMode == .axTextControl && !explicitRetrievalMode {
            context = AppPolicyContext(
                denyPaste: context.denyPaste,
                useMenuCopy: context.useMenuCopy,
                retrievalMode: .menuCopy,
                gate: context.gate
            )
        }

        return context
    }
    
    private func matchPattern(_ pattern: String, with bundleId: String) -> Bool {
        DefaultAppRules.matches(pattern: pattern, bundleID: bundleId)
    }
    
    public static let defaultRules: [AppRule] = DefaultAppRules.catalog

    /// Clears user-defined rules, returning the engine to its default state. Test-isolation hook
    /// so the shared singleton does not leak rules across test cases.
    public func reset() {
        userRules = []
    }
}
