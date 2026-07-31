import Foundation

public struct ExtensionMetadata: Sendable, Codable {
    public let identifier: String
    public let name: String
    public let actions: [ExtensionActionMetadata]
    
    enum CodingKeys: String, CodingKey {
        case identifier = "Identifier"
        case name = "Name"
        case actions = "Actions"
    }
}

public struct ExtensionActionMetadata: Sendable, Codable {
    public let title: String
    public let icon: String?
    public let script: String?
    
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case icon = "Icon"
        case script = "Script"
    }
}

@MainActor
public final class ExtensionManager: Sendable {
    public static let shared = ExtensionManager()
    
    public private(set) var loadedActions: [any Action] = []
    
    private init() {}
    
    public func loadExtensions() async {
        let nsExtensionsDir = (Constants.extensionsDirectory as NSString).expandingTildeInPath
        let extensionsURL = URL(fileURLWithPath: nsExtensionsDir)
        
        self.loadedActions = await Task.detached {
            return await Self.scanDirectory(extensionsURL)
        }.value
    }
    
    private static func scanDirectory(_ extensionsURL: URL) async -> [any Action] {
        var newActions: [any Action] = []
        let fileManager = FileManager.default
        
        guard let items = try? fileManager.contentsOfDirectory(at: extensionsURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        
        for itemURL in items {
            do {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false
                
                if isDirectory {
                    let manifestURL = itemURL.appendingPathComponent(Constants.manifestFileName)
                    if fileManager.fileExists(atPath: manifestURL.path) {
                        let actions = await loadManifestExtension(manifestURL: manifestURL, directoryURL: itemURL)
                        newActions.append(contentsOf: actions)
                    } else {
                        // Try to find standalone executable scripts in the directory
                        if let dirItems = try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: [.isDirectoryKey]) {
                            for childURL in dirItems {
                                let childResource = try? childURL.resourceValues(forKeys: [.isDirectoryKey])
                                if childResource?.isDirectory != true {
                                    if let action = await loadStandaloneScriptExtension(scriptURL: childURL) {
                                        newActions.append(action)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Try to parse standalone script
                    if let action = await loadStandaloneScriptExtension(scriptURL: itemURL) {
                        newActions.append(action)
                    }
                }
            } catch {
                continue
            }
        }
        
        return newActions
    }
    
    private static func loadManifestExtension(manifestURL: URL, directoryURL: URL) async -> [any Action] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        guard let manifest = try? JSONDecoder().decode(ExtensionMetadata.self, from: data) else { return [] }
        
        var actions: [any Action] = []
        for (index, actionMeta) in manifest.actions.enumerated() {
            let scriptName = actionMeta.script ?? "script.sh"
            let scriptURL = directoryURL.appendingPathComponent(scriptName)
            
            let actionId = "\(manifest.identifier).action.\(index)"
            let icon = parseIcon(actionMeta.icon)
            
            let action = ScriptAction(id: actionId, title: actionMeta.title, icon: icon, scriptURL: scriptURL)
            actions.append(action)
        }
        
        return actions
    }
    
    private static func loadStandaloneScriptExtension(scriptURL: URL) async -> (any Action)? {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else { return nil }
        
        let content = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: .newlines).prefix(Constants.maxHeaderLinesToScan)
        
        var title: String?
        var iconStr: String?
        var identifier: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# Title:") || trimmed.hasPrefix("// Title:") {
                title = String(trimmed.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("# Icon:") || trimmed.hasPrefix("// Icon:") {
                iconStr = String(trimmed.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("# Identifier:") || trimmed.hasPrefix("// Identifier:") {
                identifier = String(trimmed.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        guard let parsedTitle = title, !parsedTitle.isEmpty else { return nil } // Title is required
        
        let actionId = identifier ?? "com.custom.\(scriptURL.lastPathComponent)"
        let icon = parseIcon(iconStr)
        
        return ScriptAction(id: actionId, title: parsedTitle, icon: icon, scriptURL: scriptURL)
    }
    
    private static func parseIcon(_ iconStr: String?) -> ActionIcon {
        guard let iconStr = iconStr, !iconStr.isEmpty else {
            return .symbol("wand.and.stars")
        }
        if iconStr.hasPrefix("symbol(") && iconStr.hasSuffix(")") {
            let symbolName = String(iconStr.dropFirst(7).dropLast())
            return .symbol(symbolName)
        }
        return .symbol(iconStr)
    }
}
