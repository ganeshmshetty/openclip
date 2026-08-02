// ExtensionManager.swift
// OpenClip
//
// Discovers, loads, and manages installed OpenClip extensions from disk.
// Uses registration callbacks to register and unregister extension actions without direct singleton coupling to ActionRegistry.
import Foundation

public struct ExtensionOptionMetadata: Sendable, Codable {
    public let identifier: String
    public let label: String
    public let type: String
    public let defaultValue: String?
    
    public init(identifier: String, label: String, type: String, defaultValue: String? = nil) {
        self.identifier = identifier
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decode(String.self, forKey: .legacyLabel)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decode(String.self, forKey: .legacyType)
        self.defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            ?? container.decodeIfPresent(String.self, forKey: .legacyDefaultValue)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(label, forKey: .label)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier = "identifier"
        case id = "id"
        case legacyIdentifier = "Identifier"
        case label = "label"
        case legacyLabel = "Label"
        case type = "type"
        case legacyType = "Type"
        case defaultValue = "default"
        case legacyDefaultValue = "Default"
    }
}

public struct ExtensionMetadata: Sendable, Codable {
    public let identifier: String
    public let name: String
    public let actions: [ExtensionActionMetadata]
    public let options: [ExtensionOptionMetadata]?
    
    public init(identifier: String, name: String, actions: [ExtensionActionMetadata], options: [ExtensionOptionMetadata]? = nil) {
        self.identifier = identifier
        self.name = name
        self.actions = actions
        self.options = options
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .legacyIdentifier)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decode(String.self, forKey: .legacyName)
        // Support both "actions" (array) and "action" (singular object)
        if let array = try? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .actions) ?? container.decodeIfPresent([ExtensionActionMetadata].self, forKey: .legacyActions) {
            self.actions = array
        } else if let single = try? container.decodeIfPresent(ExtensionActionMetadata.self, forKey: .action) {
            self.actions = [single]
        } else {
            self.actions = []
        }
        self.options = try container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .options)
            ?? container.decodeIfPresent([ExtensionOptionMetadata].self, forKey: .legacyOptions)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(options, forKey: .options)
    }
    
    enum CodingKeys: String, CodingKey {
        case identifier = "identifier"
        case id = "id"
        case legacyIdentifier = "Identifier"
        case name = "name"
        case legacyName = "Name"
        case actions = "actions"
        case action = "action"     // singular fallback
        case legacyActions = "Actions"
        case options = "options"
        case legacyOptions = "Options"
    }
}


@MainActor
public final class ExtensionManager: Sendable {
    public static let shared = ExtensionManager()
    
    public private(set) var loadedActions: [any Action] = []
    public var actionFactory: (any ActionFactory)?
    
    private init() {}
    
    public func loadExtensions(from url: URL = Constants.extensionsDirectory) async {
        let factory = self.actionFactory
        let actions = await Task.detached {
            return await Self.scanDirectory(url, factory: factory)
        }.value
        for oldAction in self.loadedActions {
            ActionRegistry.shared.unregister(actionID: oldAction.id)
        }
        self.loadedActions = actions
        for action in actions {
            ActionRegistry.shared.register(action: action)
        }
    }
    
    /// Installs a new extension package (.openclipext folder, .zip archive, or script file) into ~/.openclip/extensions
    public func installExtension(from sourceURL: URL, targetDir: URL = Constants.extensionsDirectory) async throws -> [any Action] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw NSError(domain: "ExtensionManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Extension file does not exist."])
        }
        
        let destinationURL: URL
        if isDir.boolValue {
            // Folder installation (.openclipext)
            let folderName = sourceURL.lastPathComponent
            destinationURL = targetDir.appendingPathComponent(folderName)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)
        } else if sourceURL.pathExtension.lowercased() == "zip" {
            // Zip archive installation
            let extName = sourceURL.deletingPathExtension().lastPathComponent
            let folderName = extName.hasSuffix(".openclipext") ? extName : "\(extName).openclipext"
            destinationURL = targetDir.appendingPathComponent(folderName)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            
            // Extract zip using ditto/unzip
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", sourceURL.path, "-d", destinationURL.path]
            try process.run()
            process.waitUntilExit()
        } else {
            // Standalone script installation (.sh, .py, .js)
            let fileName = sourceURL.lastPathComponent
            destinationURL = targetDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)
        }
        
        // Reload extensions to activate installed action(s)
        await loadExtensions(from: targetDir)
        return loadedActions
    }
    
    /// Uninstalls an extension by removing its directory or file from ~/.openclip/extensions
    public func uninstallExtension(actionID: String, targetDir: URL = Constants.extensionsDirectory) async throws {
        ActionRegistry.shared.unregister(actionID: actionID)
        loadedActions.removeAll(where: { $0.id == actionID })
        
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: nil) else { return }
        
        let factory = self.actionFactory
        for itemURL in items {
            // Check if this item produced the target actionID
            let actions = await Self.scanDirectory(itemURL.deletingLastPathComponent(), factory: factory)
            if actions.contains(where: { $0.id == actionID }) {
                try? fm.removeItem(at: itemURL)
                break
            }
        }
        await loadExtensions(from: targetDir)
    }
    
    nonisolated private static func scanDirectory(_ extensionsURL: URL, factory: (any ActionFactory)? = nil) async -> [any Action] {
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
                    // Check for native openclip.json, manifest.json, or Config.json inside .openclipext package
                    let openclipManifest = itemURL.appendingPathComponent("openclip.json")
                    let legacyManifest = itemURL.appendingPathComponent("manifest.json")
                    let jsonConfigURL = itemURL.appendingPathComponent("Config.json")
                    
                    if fileManager.fileExists(atPath: openclipManifest.path) {
                        let actions = await loadManifestExtension(manifestURL: openclipManifest, directoryURL: itemURL, factory: factory)
                        newActions.append(contentsOf: actions)
                    } else if fileManager.fileExists(atPath: legacyManifest.path) {
                        let actions = await loadManifestExtension(manifestURL: legacyManifest, directoryURL: itemURL, factory: factory)
                        newActions.append(contentsOf: actions)
                    } else if fileManager.fileExists(atPath: jsonConfigURL.path) {
                        let actions = await loadManifestExtension(manifestURL: jsonConfigURL, directoryURL: itemURL, factory: factory)
                        newActions.append(contentsOf: actions)
                    } else {
                        // Scan directory for standalone executable scripts
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
    
    nonisolated private static func loadManifestExtension(manifestURL: URL, directoryURL: URL, factory: (any ActionFactory)? = nil) async -> [any Action] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        guard let manifest = try? JSONDecoder().decode(ExtensionMetadata.self, from: data) else { return [] }
        
        var actions: [any Action] = []
        for (index, actionMeta) in manifest.actions.enumerated() {
            if let factory, let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: directoryURL) {
                actions.append(action)
            } else {
                let actionId = "\(manifest.identifier).action.\(index)"
                let title = actionMeta.title ?? manifest.name
                let icon = parseIcon(actionMeta.icon, directoryURL: directoryURL)
                let regex = actionMeta.regex
                
                if let urlTemplate = actionMeta.url {
                    let action = URLTemplateAction(id: actionId, title: title, icon: icon, urlTemplate: urlTemplate, regexPattern: regex)
                    actions.append(action)
                } else {
                    let scriptName = actionMeta.script ?? Constants.defaultScriptName
                    let scriptURL = directoryURL.appendingPathComponent(scriptName)
                    let action = ScriptAction(id: actionId, title: title, icon: icon, scriptURL: scriptURL)
                    actions.append(action)
                }
            }
        }
        
        return actions
    }

    nonisolated private static func loadStandaloneScriptExtension(scriptURL: URL, factory: (any ActionFactory)? = nil) async -> (any Action)? {
        let content = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
        if let parsedAction = await OpenClipSnippetParser.parse(snippet: content) {
            return parsedAction
        }
        
        let lines = content.components(separatedBy: .newlines).prefix(Constants.maxHeaderLinesToScan)
        
        var title: String?
        var iconStr: String?
        var identifier: String?
        var urlTemplate: String?
        var regexPattern: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(Constants.titlePrefixHash) || trimmed.hasPrefix(Constants.titlePrefixSlash) || trimmed.hasPrefix("// name:") {
                title = extractHeaderValue(trimmed)
            } else if trimmed.hasPrefix(Constants.iconPrefixHash) || trimmed.hasPrefix(Constants.iconPrefixSlash) || trimmed.hasPrefix("// icon:") {
                iconStr = extractHeaderValue(trimmed)
            } else if trimmed.hasPrefix(Constants.identifierPrefixHash) || trimmed.hasPrefix(Constants.identifierPrefixSlash) || trimmed.hasPrefix("// identifier:") {
                identifier = extractHeaderValue(trimmed)
            } else if trimmed.hasPrefix("// url:") || trimmed.hasPrefix("# url:") {
                urlTemplate = extractHeaderValue(trimmed)
            } else if trimmed.hasPrefix("// regex:") || trimmed.hasPrefix("# regex:") {
                regexPattern = extractHeaderValue(trimmed)
            }
        }
        
        guard let parsedTitle = title, !parsedTitle.isEmpty else { return nil }
        
        let actionId = identifier ?? "\(Constants.customIdentifierPrefix)\(scriptURL.lastPathComponent)"
        let actionMeta = ExtensionActionMetadata(
            id: actionId,
            title: parsedTitle,
            icon: iconStr,
            script: scriptURL.lastPathComponent,
            url: urlTemplate,
            regex: regexPattern,
            type: urlTemplate != nil ? "url" : "script"
        )
        let manifest = ExtensionMetadata(identifier: actionId, name: parsedTitle, actions: [actionMeta])
        if let factory, let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: scriptURL.deletingLastPathComponent()) {
            return action
        }
        
        let icon = parseIcon(iconStr, directoryURL: scriptURL.deletingLastPathComponent())
        if let template = urlTemplate, !template.isEmpty {
            return URLTemplateAction(id: actionId, title: parsedTitle, icon: icon, urlTemplate: template, regexPattern: regexPattern)
        }
        
        if FileManager.default.isExecutableFile(atPath: scriptURL.path) || scriptURL.pathExtension == "sh" || scriptURL.pathExtension == "py" || scriptURL.pathExtension == "js" {
            return ScriptAction(id: actionId, title: parsedTitle, icon: icon, scriptURL: scriptURL)
        }
        
        return nil
    }



    
    nonisolated private static func extractHeaderValue(_ line: String) -> String {
        return String(line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last ?? "").trimmingCharacters(in: .whitespaces)
    }
    
    nonisolated public static func parseIcon(_ iconStr: String?, directoryURL: URL) -> ActionIcon {
        guard let iconStr = iconStr, !iconStr.isEmpty else {
            return .symbol(Constants.defaultIconSymbol)
        }
        if iconStr.hasPrefix(Constants.symbolPrefix) && iconStr.hasSuffix(Constants.symbolSuffix) {
            let symbolName = String(iconStr.dropFirst(Constants.symbolPrefix.count).dropLast(Constants.symbolSuffix.count))
            return .symbol(symbolName)
        }
        let lower = iconStr.lowercased()
        if Constants.imageExtensions.contains(where: { lower.hasSuffix($0) }) {
            return .local(directoryURL.appendingPathComponent(iconStr))
        }
        return .symbol(iconStr)
    }
}
