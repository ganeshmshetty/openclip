// RuleEngine.swift
// OpenClip
//
// Evaluates active selection contexts against application rules to determine if OpenClip actions should be enabled or suppressed.
import Foundation
import Combine

public struct RuleEngineConfig: Codable, Sendable {
    public let rules: [AppRule]
    /// Page patterns where the automatic popup stays off. Absent in older files.
    public let websites: [String]?

    public init(rules: [AppRule], websites: [String]? = nil) {
        self.rules = rules
        self.websites = websites
    }
}

@MainActor
public final class RuleEngine: ObservableObject, Sendable {
    public static let shared = RuleEngine()
    
    @Published public private(set) var userRules: [AppRule] = []
    @Published public private(set) var websitePatterns: [String] = []
    
    // The fully expanded rules list used for evaluation
    private var effectiveRules: [AppRule] {
        RuleEngine.expandRules(Self.defaultRules + userRules)
    }
    
    private init() {
    }
    
    public func loadRules(from url: URL) async {
        let logger = Log.settings
        let loadedConfig = await Task.detached { () -> RuleEngineConfig? in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let config = try decoder.decode(RuleEngineConfig.self, from: data)
                logger.info("Successfully loaded \(config.rules.count) rules from \(url.lastPathComponent, privacy: .public)")
                return config
            } catch {
                logger.error("Failed to load rules from \(url.lastPathComponent, privacy: .public): \(error.localizedDescription)")
                return nil
            }
        }.value
        
        if let loadedConfig {
            self.userRules = loadedConfig.rules
            self.websitePatterns = loadedConfig.websites ?? []
        }
    }
    
    public func saveRules(to url: URL) {
        let config = RuleEngineConfig(rules: userRules, websites: websitePatterns)
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

    // MARK: - Websites

    /// Adds a page pattern unless it duplicates an existing entry. Users configure this list; there
    /// are no built-in entries.
    public func addWebsite(_ pattern: String, saveURL: URL = Constants.rulesFileURL) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !websitePatterns.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        websitePatterns.append(trimmed)
        saveRules(to: saveURL)
    }

    public func removeWebsite(_ pattern: String, saveURL: URL = Constants.rulesFileURL) {
        guard let index = websitePatterns.firstIndex(where: { $0.caseInsensitiveCompare(pattern) == .orderedSame }) else { return }
        websitePatterns.remove(at: index)
        saveRules(to: saveURL)
    }

    public func isWebsiteBlocked(_ url: URL) -> Bool {
        matchedWebsitePattern(for: url) != nil
    }

    public func matchedWebsitePattern(for url: URL) -> String? {
        websitePatterns.first { WebsitePattern.matches(url, pattern: $0) }
    }

    /// Removes every pattern that matches `url`, so "Enable on this page" really unblocks it even
    /// when a broad and a specific rule overlap.
    public func removeWebsites(matching url: URL, saveURL: URL = Constants.rulesFileURL) {
        let matching = websitePatterns.filter { WebsitePattern.matches(url, pattern: $0) }
        guard !matching.isEmpty else { return }
        websitePatterns.removeAll { pattern in
            matching.contains { $0.caseInsensitiveCompare(pattern) == .orderedSame }
        }
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
                disabled: rule.disabled,
                hotkeyOnly: rule.hotkeyOnly,
                useMenuCopy: rule.useMenuCopy,
                denyPaste: rule.denyPaste,
                retrievalMode: rule.retrievalMode,
                gate: rule.gate
            )
        }
    }
    
    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        resolvePolicies(for: AppIdentity(bundleIdentifier: bundleIdentifier))
    }

    public func resolvePolicies(for identity: AppIdentity) -> AppPolicyContext {
        var context = AppPolicyContext(blockedWebsitePatterns: websitePatterns)
        var explicitRetrievalMode = false

        for rule in effectiveRules {
            if rule.bundleIdentifiers.contains(where: { DefaultAppRules.matches(pattern: $0, identity: identity) }) {
                if rule.retrievalMode != nil {
                    explicitRetrievalMode = true
                }
                context = AppPolicyContext(
                    disabled: rule.disabled ?? context.disabled,
                    hotkeyOnly: rule.hotkeyOnly ?? context.hotkeyOnly,
                    denyPaste: rule.denyPaste ?? context.denyPaste,
                    useMenuCopy: rule.useMenuCopy ?? context.useMenuCopy,
                    retrievalMode: rule.retrievalMode ?? context.retrievalMode,
                    gate: rule.gate ?? context.gate,
                    blockedWebsitePatterns: context.blockedWebsitePatterns
                )
            }
        }

        // Legacy alias: a `use-menu-copy: true` rule that never set an explicit retrieval mode
        // resolves to `.menuCopy`, preserving old rule files' behavior. A matching rule that
        // explicitly supplied `retrieval-mode` (even `.axTextControl`) opts out of the conversion.
        if context.useMenuCopy && context.retrievalMode == .axTextControl && !explicitRetrievalMode {
            context = AppPolicyContext(
                disabled: context.disabled,
                hotkeyOnly: context.hotkeyOnly,
                denyPaste: context.denyPaste,
                useMenuCopy: context.useMenuCopy,
                retrievalMode: .menuCopy,
                gate: context.gate,
                blockedWebsitePatterns: context.blockedWebsitePatterns
            )
        }

        return context
    }
    
    public static let defaultRules: [AppRule] = DefaultAppRules.catalog

    /// Clears user-defined rules and websites, returning the engine to its default state.
    /// Test-isolation hook so the shared singleton does not leak rules across test cases.
    public func reset() {
        userRules = []
        websitePatterns = []
    }
}
