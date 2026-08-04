// ExtensionManager.swift
// OpenClip
//
// Discovers, loads, and manages installed OpenClip extensions from disk.
// Applies the uniform action-ID rule (explicit id with bare-slug expansion, else index-based)
// and keeps `group` actions schema-only (not registered as runnable).
// Reports registration changes to the ActionRegistry via the onRegister/onUnregister
// callbacks that ActionCoordinator.loadInitialState() wires. Does not touch ActionRegistry directly.
import Foundation

public struct ExtensionOptionMetadata: Sendable, Codable, Equatable {
    public let identifier: String
    public let label: String
    public let type: String
    public let defaultValue: String?
    public let values: [String]?
    
    public init(identifier: String, label: String, type: String, defaultValue: String? = nil, values: [String]? = nil) {
        self.identifier = identifier
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.values = values
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
        self.values = try container.decodeIfPresent([String].self, forKey: .values)
            ?? container.decodeIfPresent([String].self, forKey: .valuesOptions)
            ?? container.decodeIfPresent([String].self, forKey: .valuesLegacyOptions)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(label, forKey: .label)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(values, forKey: .values)
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
        case values = "values"
        case valuesOptions = "options"
        case valuesLegacyOptions = "Options"
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
    
    /// Wired by `ActionCoordinator.loadInitialState()`; the manager never touches the registry directly.
    public var onRegister: ((any Action) -> Void)?
    public var onUnregister: ((String) -> Void)?
    
    public private(set) var loadedActions: [any Action] = []
    public var actionFactory: (any ActionFactory)?
    
    private init() {}
    
    public func loadExtensions(from url: URL = Constants.extensionsDirectory) async {
        let factory = self.actionFactory
        let actions = await Task.detached {
            return await Self.scanDirectory(url, factory: factory)
        }.value
        for oldAction in self.loadedActions {
            onUnregister?(oldAction.id)
        }
        self.loadedActions = actions
        for action in actions {
            onRegister?(action)
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
            // Unzip to a temp staging dir, then find the .openclipext folder inside and move it.
            let stagingDir = targetDir.appendingPathComponent(".install_staging_\(UUID().uuidString)")
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingDir) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", sourceURL.path, "-d", stagingDir.path]
            try process.run()
            process.waitUntilExit()

            // Find the .openclipext folder within the staging dir (zip may contain it at root)
            let stagedItems = (try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let packageURL = stagedItems.first {
                var d: ObjCBool = false
                fm.fileExists(atPath: $0.path, isDirectory: &d)
                return d.boolValue && Constants.isPathSafe(destinationURL: $0, baseDirectory: stagingDir)
            } ?? stagingDir

            guard Constants.isPathSafe(destinationURL: packageURL, baseDirectory: stagingDir) else {
                throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive contains an unsafe path."])
            }

            let folderName = packageURL.lastPathComponent
            destinationURL = targetDir.appendingPathComponent(folderName)
            guard Constants.isPathSafe(destinationURL: destinationURL, baseDirectory: targetDir) else {
                throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive destination is unsafe."])
            }
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: packageURL, to: destinationURL)
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
    
    /// Uninstalls an extension by removing its directory or file from ~/.openclip/extensions.
    /// Matches the extension folder by reading the manifest identifier, which is the prefix of generated action IDs.
    public func uninstallExtension(actionID: String, targetDir: URL = Constants.extensionsDirectory) async throws {
        onUnregister?(actionID)
        loadedActions.removeAll(where: { $0.id == actionID })

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        for itemURL in items {
            // Skip hidden/staging dirs
            guard !itemURL.lastPathComponent.hasPrefix(".") else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

            var matched = false

            if isDir.boolValue {
                // Read manifest identifier directly — generated action IDs are "<identifier>.action.<n>"
                let manifestCandidates = ["openclip.json", "manifest.json", "Config.json"]
                for fname in manifestCandidates {
                    let manifestURL = itemURL.appendingPathComponent(fname)
                    if let data = try? Data(contentsOf: manifestURL),
                       let meta = try? JSONDecoder().decode(ExtensionMetadata.self, from: data) {
                        // actionID starts with manifest identifier at a component boundary
                        // (e.g. "com.openclip.applemusic.action.0" vs "com.openclip.applemusic"),
                        // so com.foo never matches com.foobar.
                        let actionIDPrefix = meta.identifier + "."
                        if actionID == meta.identifier || actionID.hasPrefix(actionIDPrefix) {
                            matched = true
                        }
                        break
                    }
                }
            } else {
                // Standalone script: generated id uses filename
                if actionID.contains(itemURL.deletingPathExtension().lastPathComponent) {
                    matched = true
                }
            }

            if matched {
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
            if let factory {
                // createActions flattens `.group` entries into a GroupAction row + sub-actions
                // (Phase 8); non-group kinds return a single entry.
                actions.append(contentsOf: await factory.createActions(metadata: actionMeta, manifest: manifest, directoryURL: directoryURL, index: index))
            } else if actionMeta.kind != .group {
                let actionId = uniformActionID(metadata: actionMeta, manifest: manifest, index: index)
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
        if let factory, let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: scriptURL.deletingLastPathComponent(), index: 0) {
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

    /// Uniform action ID rule: an explicit `metadata.id` wins (a bare slug without a dot is prefixed with
    /// the manifest identifier); otherwise the ID is stable by action index (`\(identifier).action.\(index)`).
    /// Title-based IDs are gone.
    nonisolated public static func uniformActionID(metadata: ExtensionActionMetadata, manifest: ExtensionMetadata, index: Int) -> String {
        if let id = metadata.id {
            return id.contains(".") ? id : "\(manifest.identifier).\(id)"
        }
        return "\(manifest.identifier).action.\(index)"
    }
}
