// ExtensionManager.swift
// OpenClip
//
// Discovers, loads, and manages installed OpenClip extensions from disk.
// Applies the uniform action-ID rule (explicit id with bare-slug expansion, else index-based)
// and keeps `group` actions schema-only (not registered as runnable).
// Reports registration changes to the ActionRegistry via the onRegister/onUnregister
// callbacks that ActionCoordinator.loadInitialState() wires. Does not touch ActionRegistry directly.
import Foundation




@MainActor
public final class ExtensionManager: Sendable {
    public static let shared = ExtensionManager()
    
    /// Wired by `ActionCoordinator.loadInitialState()`; the manager never touches the registry directly.
    public var onRegister: ((any Action) -> Void)?
    public var onUnregister: ((String) -> Void)?
    
    public private(set) var loadedActions: [any Action] = []
    public var actionFactory: (any ActionFactory)?
    public var optionWriter: (any ActionOptionWriting)?
    
    /// Persistence for the trust gate. When nil the manager skips gating entirely (pre-existing
    /// behavior); production sets it in AppDelegate, tests set a MemorySettingsStore.
    public var settingsStore: (any SettingsStore)?
    
    /// Supplies the running app version for `minOpenClipVersion` checks. Overridable for tests.
    public var appVersionProvider: @Sendable () -> String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
    
    /// Trust events for the app target to surface as user notifications.
    public var onTrustChange: ((ExtensionTrustChange) -> Void)?
    
    private init() {}

    /// Clears loaded actions and wiring (callbacks, factory), returning the manager to its
    /// pristine state. Test-isolation hook so the shared singleton does not leak loaded actions,
    /// registration callbacks, or a stale factory across test cases.
    public func reset() {
        loadedActions = []
        onRegister = nil
        onUnregister = nil
        actionFactory = nil
        optionWriter = nil
        settingsStore = nil
        onTrustChange = nil
    }
    
    public func loadExtensions(from url: URL = Constants.extensionsDirectory) async {
        let factory = self.actionFactory
        let scanned = await Task.detached {
            // Reference the type by name (not `Self`) — `Self.X` inside a Task.detached closure
            // trips a Swift 6 region-based-isolation checker bug.
            return await ExtensionManager.scanDirectory(url, factory: factory)
        }.value
        
        let finalActions: [any Action]
        if let settings = self.settingsStore {
            let plan = ExtensionTrustGate.evaluate(
                actions: scanned,
                in: url,
                trust: settings.get(.extensionTrust),
                hashes: settings.get(.extensionTrustHashes),
                sources: settings.get(.extensionSources),
                isMigrated: settings.get(.extensionTrustMigrated),
                appVersion: self.appVersionProvider()
            )
            if plan.trustChanged { settings.set(.extensionTrust, value: plan.trust) }
            if plan.hashesChanged { settings.set(.extensionTrustHashes, value: plan.hashes) }
            if plan.sourcesChanged { settings.set(.extensionSources, value: plan.sources) }
            if plan.migratedChanged { settings.set(.extensionTrustMigrated, value: plan.isMigrated) }
            finalActions = plan.actions
            for event in plan.events {
                onTrustChange?(event)
            }
        } else {
            finalActions = scanned
        }
        
        let newIDs = Set(finalActions.map { $0.id })
        // Diff the previous vs refreshed action IDs. Only unregister IDs that are permanently gone;
        // retained IDs are replaced in place via onRegister (register(action:)), so their
        // .actionOrder entries survive the reload instead of being pruned by a full
        // unregister-then-register cycle.
        for oldAction in self.loadedActions where !newIDs.contains(oldAction.id) {
            onUnregister?(oldAction.id)
        }
        self.loadedActions = finalActions
        for action in finalActions {
            onRegister?(action)
        }
    }
    
    /// Installs a new extension package (.openclipext folder, .zip archive, or script file) into ~/.openclip/extensions
    public func installExtension(from sourceURL: URL, targetDir: URL = Constants.extensionsDirectory, source: String? = nil) async throws -> [any Action] {
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
            let stagingDir = targetDir.appendingPathComponent(".install_staging_\(UUID().uuidString)")
            
            // 1. Validate entries for containment BEFORE extraction to prevent Zip-Slip
            try await ExtensionManager.validateZipEntries(at: sourceURL, stagingDir: stagingDir)

            // 2. Unzip to a temp staging dir, then find the .openclipext folder inside and move it.
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingDir) }

            // Unzip via the shared async subprocess runner — never `waitUntilExit` on the main
            // actor. Non-zero exit throws here (unzip failure surfaces instead of a silent empty
            // staging dir).
            _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                arguments: ["-q", sourceURL.path, "-d", stagingDir.path],
                environment: [:]
            ))
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
        
        // Resolve installed package identifier so we return only actions belonging to this package.
        let installedPackageID: String?
        var isDestDir: ObjCBool = false
        if fm.fileExists(atPath: destinationURL.path, isDirectory: &isDestDir), isDestDir.boolValue {
            if let manifestURL = ExtensionManifestStore.manifestFileURL(in: destinationURL),
               let manifest = ExtensionManifestStore.readManifest(at: manifestURL) {
                installedPackageID = manifest.identifier
            } else {
                installedPackageID = nil
            }
        } else {
            if let action = await Self.loadStandaloneScriptExtension(scriptURL: destinationURL, factory: self.actionFactory) {
                installedPackageID = ActionIdentity.extensionPackageID(of: action) ?? action.id
            } else {
                installedPackageID = "\(Constants.customIdentifierPrefix)\(destinationURL.lastPathComponent)"
            }
        }

        // Record package source if not already explicitly recorded (e.g. file packages default to "package")
        if let installedPackageID {
            if let source {
                prepareInstall(source: source, packageID: installedPackageID)
            } else if self.settingsStore?.get(.extensionSources)[installedPackageID] == nil {
                prepareInstall(source: ExtensionSource.package.rawValue, packageID: installedPackageID)
            }
        }

        // Reload extensions to activate installed action(s)
        await loadExtensions(from: targetDir)

        if let installedPackageID {
            let newlyInstalled = loadedActions.filter {
                ActionIdentity.extensionPackageID(of: $0) == installedPackageID || $0.id == installedPackageID
            }
            if !newlyInstalled.isEmpty {
                return newlyInstalled
            }
        }
        return loadedActions
    }
    
    /// Seeds `extensionSources[packageID] = source` ahead of a load so store installs auto-trust
    /// during the subsequent gating pass. Call before `loadExtensions`/`installExtension`.
    public func prepareInstall(source: String, packageID: String) {
        guard let settings = self.settingsStore else { return }
        var sources = settings.get(.extensionSources)
        sources[packageID] = source
        settings.set(.extensionSources, value: sources)
    }

    /// Sets or updates the extension source ("store", "package", "developer").
    public func setSource(_ source: String, for packageID: String) {
        guard let settings = self.settingsStore else { return }
        var sources = settings.get(.extensionSources)
        sources[packageID] = source
        settings.set(.extensionSources, value: sources)
    }
    
    /// Trust-model Enable: record the package's current content hash and mark it trusted, then
    /// reload so its real actions register. The only way to restore a gated/revoked package.
    /// Fail-closed: nothing is persisted unless the content fingerprint resolves.
    public func enablePackage(packageID: String, in directory: URL = Constants.extensionsDirectory) async {
        guard let settings = self.settingsStore else { return }
        guard let hash = ExtensionPackageHashResolver.packageHash(forPackageID: packageID, in: directory) else { return }
        var trust = settings.get(.extensionTrust)
        trust[packageID] = ExtensionTrustState.trusted.rawValue
        settings.set(.extensionTrust, value: trust)
        var hashes = settings.get(.extensionTrustHashes)
        hashes[packageID] = hash
        settings.set(.extensionTrustHashes, value: hashes)
        await loadExtensions(from: directory)
    }
    
    /// Trust-model Disable: mark the package revoked (an explicit user "no"), then reload so its
    /// real actions are replaced by the gated placeholder.
    public func disablePackage(packageID: String, in directory: URL = Constants.extensionsDirectory) async {
        guard let settings = self.settingsStore else { return }
        var trust = settings.get(.extensionTrust)
        trust[packageID] = ExtensionTrustState.revoked.rawValue
        settings.set(.extensionTrust, value: trust)
        await loadExtensions(from: directory)
    }

    /// Re-records the trust fingerprint after an authorized in-app edit (EditActionSheet save) so
    /// tamper detection does not falsely flag the changed files. Only an already-`trusted` package
    /// is re-trusted: a `revoked` (explicit user "no") or never-enabled (`seen`) package keeps its
    /// trust state — a config-sheet save must never double as a consent flow. The next explicit
    /// Enable records the new hash either way.
    public func retrustAfterAuthorizedEdit(packageID: String, in directory: URL = Constants.extensionsDirectory) async {
        guard let settings = self.settingsStore else { return }
        guard settings.get(.extensionTrust)[packageID] == ExtensionTrustState.trusted.rawValue else {
            await loadExtensions(from: directory)
            return
        }
        await enablePackage(packageID: packageID, in: directory)
    }
    
    /// Uninstalls an extension by removing its directory or file from ~/.openclip/extensions.
    /// Matches the extension folder by reading the manifest identifier, which is the prefix of generated action IDs.
    public func uninstallExtension(actionID: String, targetDir: URL = Constants.extensionsDirectory) async throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey])
        var removed = false
        var removedPackageID: String?

        for itemURL in items {
            // Skip hidden/staging dirs
            guard !itemURL.lastPathComponent.hasPrefix(".") else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

            var matched = false

            if isDir.boolValue {
                // Read manifest identifier directly — generated action IDs are "<identifier>.action.<n>"
                for fname in ExtensionManifestStore.candidateFileNames {
                    let manifestURL = itemURL.appendingPathComponent(fname)
                    if let meta = ExtensionManifestStore.readManifest(at: manifestURL) {
                        // actionID starts with manifest identifier at a component boundary
                        // (e.g. "com.openclip.applemusic.action.0" vs "com.openclip.applemusic"),
                        // so com.foo never matches com.foobar.
                        let actionIDPrefix = meta.identifier + "."
                        if actionID == meta.identifier || actionID.hasPrefix(actionIDPrefix) {
                            matched = true
                            removedPackageID = meta.identifier
                            if let optionWriter {
                                for (index, actionMeta) in meta.actions.enumerated() {
                                    let id = ExtensionManager.uniformActionID(metadata: actionMeta, manifest: meta, index: index)
                                    let options = (meta.options ?? []) + (actionMeta.options ?? [])
                                    for optMeta in options {
                                        let opt = ExtensionOption(
                                            identifier: optMeta.identifier,
                                            label: optMeta.label,
                                            type: ExtensionOptionType(rawValue: optMeta.type) ?? .string,
                                            defaultValue: optMeta.defaultValue,
                                            options: optMeta.values
                                        )
                                        optionWriter.clearValue(actionID: id, option: opt)
                                    }
                                }
                            }
                        }
                        break
                    }
                }
            } else {
                // Standalone script: resolve by the loader's exact id rules (mirroring
                // ExtensionPackageHashResolver.packageHash(forPackageID:)) — the synthesized
                // "com.custom.<filename>" id or a declared `// Identifier:` header. Never a
                // filename substring: "a" is contained in "com.custom.alpha.sh", so a raw
                // contains() check deletes the wrong script, and header-identified scripts
                // would never match their filename at all.
                let synthesized = "\(Constants.customIdentifierPrefix)\(itemURL.lastPathComponent)"
                if actionID == synthesized || ExtensionPackageHashResolver.declaredIdentifier(of: itemURL) == actionID {
                    matched = true
                    // The standalone script's chrome package id equals its action id.
                    removedPackageID = actionID
                }
            }

            if matched {
                try fm.removeItem(at: itemURL)
                removed = true
                break
            }
        }

        guard removed else {
            throw NSError(domain: "ExtensionManager", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No extension found for action \(actionID)."])
        }
        if let packageID = removedPackageID, let settings = self.settingsStore {
            var sources = settings.get(.extensionSources)
            sources.removeValue(forKey: packageID)
            settings.set(.extensionSources, value: sources)
            var trust = settings.get(.extensionTrust)
            trust.removeValue(forKey: packageID)
            settings.set(.extensionTrust, value: trust)
            var hashes = settings.get(.extensionTrustHashes)
            hashes.removeValue(forKey: packageID)
            settings.set(.extensionTrustHashes, value: hashes)
        }
        if let packageID = removedPackageID {
            let actionsToUnregister = loadedActions.filter {
                ActionIdentity.extensionPackageID(of: $0) == packageID || $0.id == packageID || $0.id.hasPrefix(packageID + ".")
            }
            for act in actionsToUnregister {
                onUnregister?(act.id)
            }
            loadedActions.removeAll {
                ActionIdentity.extensionPackageID(of: $0) == packageID || $0.id == packageID || $0.id.hasPrefix(packageID + ".")
            }
        } else {
            onUnregister?(actionID)
            loadedActions.removeAll(where: { $0.id == actionID })
        }
        await loadExtensions(from: targetDir)
    }
    
    /// Test-only seam exposing the private scan over a directory. The real path funnels through
    /// `loadExtensions` (which applies trust gating); tests use this to obtain raw scanned actions.
    nonisolated public static func scanActionsForTest(in url: URL, factory: (any ActionFactory)? = nil) async -> [any Action] {
        await scanDirectory(url, factory: factory)
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
                    let manifestFile = ExtensionManifestStore.manifestFileURL(in: itemURL)

                    if let manifestFile {
                        let actions = await loadManifestExtension(manifestURL: manifestFile, directoryURL: itemURL, factory: factory)
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
                Log.extensions.error("Failed to load extension from \(itemURL.path, privacy: .public): \(error.localizedDescription)")
                continue
            }
        }
        
        return newActions
    }
    
    nonisolated private static func loadManifestExtension(manifestURL: URL, directoryURL: URL, factory: (any ActionFactory)? = nil) async -> [any Action] {
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            Log.extensions.error("Failed to read extension manifest at \(manifestURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
        let manifest: ExtensionMetadata
        do {
            manifest = try ExtensionManifestStore.decodeManifest(from: data)
        } catch {
            Log.extensions.error("Failed to decode extension manifest at \(manifestURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        // Validation pass: unknown action kinds, missing required fields, and any declared
        // capability outside the (empty) known set reject the whole package instead of silently
        // mis-routing or skipping.
        let validator = ManifestValidator.shared
        let record = validator.validate(manifest, data: data)
        guard record.isValid else {
            let details = record.issues.map(\.description).joined(separator: "; ")
            Log.extensions.error("Extension manifest rejected at \(manifestURL.path, privacy: .public): \(details, privacy: .public)")
            return []
        }
        Log.extensions.notice("Loaded extension manifest \(manifest.identifier, privacy: .public) (v\(record.declaredVersion ?? "-", privacy: .public), schema \(record.schemaVersion, privacy: .public), \(manifest.actions.count) action(s), sha256 \(record.fingerprint, privacy: .public))")

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
                // Stamp the manifest-identifier chrome here just like the factory path, so the
                // trust gate (which groups packages by `chrome.source`) sees the package id
                // (`com.t.first`), not the uniform action id (`com.t.first.action.0`).
                let extensionChrome = ActionChrome(
                    badge: .extensionPkg(manifest.name),
                    rowStyle: .standard,
                    popupBehavior: .perform,
                    source: .extensionPkg(packageID: manifest.identifier)
                )
                
                if let urlTemplate = actionMeta.url {
                    let action = URLTemplateAction(id: actionId, title: title, icon: icon, urlTemplate: urlTemplate, regexPattern: regex, chrome: extensionChrome)
                    actions.append(action)
                } else {
                    let scriptName = actionMeta.script ?? Constants.defaultScriptName
                    let scriptURL = directoryURL.appendingPathComponent(scriptName)
                    guard !scriptName.hasPrefix("/"),
                          !scriptName.hasPrefix("~"),
                          !scriptName.contains(":"),
                          Constants.isPathSafe(destinationURL: scriptURL, baseDirectory: directoryURL),
                          scriptURL.standardized.path != directoryURL.standardized.path else {
                        Log.extensions.error("Script path escapes extension directory: \(scriptName, privacy: .public)")
                        continue
                    }
                    let action = ScriptAction(id: actionId, title: title, icon: icon, scriptURL: scriptURL, chrome: extensionChrome)
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

    /// Validates all entry paths in a zip archive using `unzip -Z1` before extraction to prevent Zip-Slip vulnerabilities.
    public static func validateZipEntries(at zipURL: URL, stagingDir: URL) async throws {
        let listOutput = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z1", zipURL.path],
            environment: [:]
        ))

        let lines = listOutput.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        for entry in lines {
            guard !entry.isEmpty else { continue }
            if entry.hasPrefix("/") || entry.contains("../") || entry.contains("/..") || entry == ".." {
                throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive contains an unsafe entry path: \(entry)"])
            }
            let candidateURL = stagingDir.appendingPathComponent(entry)
            guard Constants.isPathSafe(destinationURL: candidateURL, baseDirectory: stagingDir) else {
                throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive entry is outside staging directory: \(entry)"])
            }
        }

        // Reject symbolic-link entries before extraction. A symlink created by the archive could
        // be followed by a later entry (or by the install's own move) to write outside stagingDir.
        let verboseOutput = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z", "-v", zipURL.path],
            environment: [:]
        ))
        if let symlinkName = firstSymlinkEntry(in: verboseOutput.stdout) {
            throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive contains a symbolic-link entry: \(symlinkName)"])
        }
    }

    /// Scans `unzip -Z -v` output for the first entry whose Unix type bits mark a symbolic link
    /// (`0o120000`, S_IFLNK). Each `Central directory entry #N:` block names its entry on the
    /// following content line; the `Unix file attributes (<octal> octal)` line carries its mode.
    private static func firstSymlinkEntry(in verboseOutput: String) -> String? {
        var currentName: String?
        for line in verboseOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Central directory entry") {
                currentName = nil
            } else if trimmed.hasPrefix("Unix file attributes") {
                guard let octal = unixModeOctal(from: trimmed) else { continue }
                if octal & 0o170000 == 0o120000 {
                    return currentName ?? "unknown"
                }
            } else if currentName == nil, !trimmed.isEmpty, !trimmed.hasPrefix("-") {
                currentName = trimmed
            }
        }
        return nil
    }

    /// Extracts the octal mode (e.g. `120777`) from a `Unix file attributes (120777 octal):` line.
    private static func unixModeOctal(from attributeLine: String) -> Int? {
        guard let open = attributeLine.firstIndex(of: "("),
              let close = attributeLine[open...].firstIndex(of: ")") else { return nil }
        let content = attributeLine[attributeLine.index(after: open)..<close]
        let octal = content.split(separator: " ").first ?? content
        return Int(octal, radix: 8)
    }
}
