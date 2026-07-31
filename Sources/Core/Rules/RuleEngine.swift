import Foundation
import Combine
import os

public struct RuleEngineConfig: Codable, Sendable {
    public let rules: [AppRule]
    
    public init(rules: [AppRule]) {
        self.rules = rules
    }
}

@MainActor
public final class RuleEngine: ObservableObject, Sendable {
    public static let shared = RuleEngine()
    
    @Published public private(set) var userRules: [AppRule] = []
    private var allExpandedRules: [AppRule] = []
    private let logger = Logger(subsystem: "com.openclip", category: "RuleEngine")
    
    private init() {
        self.userRules = Self.defaultRules
        self.allExpandedRules = RuleEngine.expandRules(Self.defaultRules)
    }
    
    public func loadRules(from url: URL = Constants.rulesFileURL) async {
        let logger = self.logger
        let loadedRules = await Task.detached { () -> [AppRule]? in
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
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
        
        if let loadedRules = loadedRules, !loadedRules.isEmpty {
            self.userRules = loadedRules
            self.allExpandedRules = RuleEngine.expandRules(loadedRules)
        } else {
            self.userRules = Self.defaultRules
            self.allExpandedRules = RuleEngine.expandRules(Self.defaultRules)
        }
    }
    
    public func addRule(_ rule: AppRule, saveTo url: URL = Constants.rulesFileURL) {
        userRules.append(rule)
        allExpandedRules = RuleEngine.expandRules(userRules)
        saveRules(to: url)
    }
    
    public func deleteRule(id: String, saveTo url: URL = Constants.rulesFileURL) {
        userRules.removeAll(where: { $0.bundleIdentifiers.contains(id) })
        allExpandedRules = RuleEngine.expandRules(userRules)
        saveRules(to: url)
    }
    
    public func deleteRule(at indexSet: IndexSet, saveTo url: URL = Constants.rulesFileURL) {
        for index in indexSet.sorted().reversed() {
            if index >= 0 && index < userRules.count {
                userRules.remove(at: index)
            }
        }
        allExpandedRules = RuleEngine.expandRules(userRules)
        saveRules(to: url)
    }
    
    public func saveRules(to url: URL = Constants.rulesFileURL) {
        let rulesToSave = userRules
        Task.detached {
            do {
                let parentDir = url.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: parentDir.path) {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                let config = RuleEngineConfig(rules: rulesToSave)
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(config)
                try data.write(to: url)
            } catch {
                print("Failed to save rules: \(error)")
            }
        }
    }
    
    private static func expandRules(_ rules: [AppRule]) -> [AppRule] {
        return rules.map { rule in
            var expandedIdentifiers: [String] = []
            for id in rule.bundleIdentifiers {
                if id == ":safari-group:" {
                    expandedIdentifiers.append(contentsOf: ["com.apple.Safari", "com.apple.SafariTechnologyPreview"])
                } else if id == ":chromium-group:" {
                    expandedIdentifiers.append(contentsOf: ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac"])
                } else if id == ":firefox-group:" {
                    expandedIdentifiers.append("org.mozilla.firefox")
                } else if id == ":arc-group:" {
                    expandedIdentifiers.append("company.thebrowser.Browser")
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
                grabKeyboard: rule.grabKeyboard,
                browserAddressBar: rule.browserAddressBar,
                assumePaste: rule.assumePaste,
                lenientSelect: rule.lenientSelect
            )
        }
    }
    
    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        var context = AppPolicyContext.default
        
        for rule in allExpandedRules {
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
        if pattern == "*" { return true }
        if pattern == bundleId { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return bundleId == prefix || bundleId.hasPrefix(prefix + ".")
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
