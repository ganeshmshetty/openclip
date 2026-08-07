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
                logger.info("Successfully loaded \(config.rules.count) rules from \(url.path, privacy: .public)")
                return config.rules
            } catch {
                logger.error("Failed to load rules from \(url.path, privacy: .public): \(error.localizedDescription)")
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
            Log.settings.info("Successfully saved \(self.userRules.count) rules to \(url.path, privacy: .public)")
        } catch {
            Log.settings.error("Failed to save rules to \(url.path, privacy: .public): \(error.localizedDescription)")
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
                } else if id == ":safari-group:" {
                    expandedIdentifiers.append(contentsOf: DefaultAppRules.safariGroup)
                } else if id == ":chromium-group:" {
                    expandedIdentifiers.append(contentsOf: DefaultAppRules.chromiumGroup)
                } else if id == ":firefox-group:" {
                    expandedIdentifiers.append(contentsOf: DefaultAppRules.firefoxGroup)
                } else if id == ":arc-group:" {
                    expandedIdentifiers.append(contentsOf: DefaultAppRules.arcGroup)
                } else {
                    expandedIdentifiers.append(id)
                }
            }
            return AppRule(
                bundleIdentifiers: expandedIdentifiers,
                denyFormatting: rule.denyFormatting,
                denyProbe: rule.denyProbe,
                denyPreprobe: rule.denyPreprobe,
                grabPasteboard: rule.grabPasteboard,
                assumePaste: rule.assumePaste,
                useMenuCopy: rule.useMenuCopy
            )
        }
    }
    
    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        var context = AppPolicyContext.default
        
        for rule in effectiveRules {
            if rule.bundleIdentifiers.contains(where: { matchPattern($0, with: bundleIdentifier) }) {
                context = AppPolicyContext(
                    denyFormatting: rule.denyFormatting ?? context.denyFormatting,
                    denyProbe: rule.denyProbe ?? context.denyProbe,
                    denyPreprobe: rule.denyPreprobe ?? context.denyPreprobe,
                    grabPasteboard: rule.grabPasteboard ?? context.grabPasteboard,
                    assumePaste: rule.assumePaste ?? context.assumePaste,
                    useMenuCopy: rule.useMenuCopy ?? context.useMenuCopy
                )
            }
        }
        
        return context
    }
    
    private func matchPattern(_ pattern: String, with bundleId: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == bundleId { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return bundleId == prefix || bundleId.hasPrefix(prefix + ".")
        }
        return false
    }
    
    public static let defaultRules: [AppRule] = DefaultAppRules.catalog

    /// Clears user-defined rules, returning the engine to its default state. Test-isolation hook
    /// so the shared singleton does not leak rules across test cases.
    public func reset() {
        userRules = []
    }
}
