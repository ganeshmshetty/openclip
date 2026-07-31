import Foundation
import os

public struct RuleEngineConfig: Codable, Sendable {
    public let rules: [AppRule]
}

@MainActor
public final class RuleEngine: Sendable {
    public static let shared = RuleEngine()
    
    private var rules: [AppRule] = []
    private let logger = Logger(subsystem: "com.openclip", category: "RuleEngine")
    
    private init() {
        self.rules = Self.defaultRules
    }
    
    public func loadRules(from url: URL) async {
        let logger = self.logger
        let loadedRules = await Task.detached { () -> [AppRule]? in
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let config = try decoder.decode(RuleEngineConfig.self, from: data)
                logger.info("Successfully loaded \(config.rules.count) rules from \(url.path)")
                return config.rules
            } catch {
                logger.error("Failed to load rules from \(url.path): \(error.localizedDescription)")
                return nil
            }
        }.value
        
        if let loadedRules = loadedRules {
            self.rules = loadedRules
        }
    }
    
    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        var context = AppPolicyContext.default
        
        for rule in rules {
            if rule.bundleIdentifiers.contains(where: { matchPattern($0, with: bundleIdentifier) }) {
                context = AppPolicyContext(
                    denyFormatting: rule.denyFormatting ?? context.denyFormatting,
                    denyProbe: rule.denyProbe ?? context.denyProbe,
                    denyPreprobe: rule.denyPreprobe ?? context.denyPreprobe,
                    grabPasteboard: rule.grabPasteboard ?? context.grabPasteboard,
                    grabKeyboard: rule.grabKeyboard ?? context.grabKeyboard,
                    browserAddressBar: rule.browserAddressBar ?? context.browserAddressBar,
                    assumePaste: rule.assumePaste ?? context.assumePaste,
                    lenientSelect: rule.lenientSelect ?? context.lenientSelect
                )
            }
        }
        
        return context
    }
    
    private func matchPattern(_ pattern: String, with bundleId: String) -> Bool {
        if pattern == bundleId { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return bundleId.hasPrefix(prefix)
        }
        return false
    }
    
    public static let defaultRules: [AppRule] = [
        AppRule(
            bundleIdentifiers: ["com.jetbrains.*", "com.apple.Terminal", "com.sublimetext.*"],
            denyFormatting: true,
            grabKeyboard: true
        ),
        AppRule(
            bundleIdentifiers: ["md.obsidian", "com.skype.skype", "com.evernote.Evernote"],
            grabPasteboard: true
        ),
        AppRule(
            bundleIdentifiers: ["net.ankiweb.dtop"],
            assumePaste: true
        )
    ]
}
