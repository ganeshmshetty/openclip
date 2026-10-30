// ExtensionManager.swift
// OpenClip
//
// Discovers, loads, and manages installed extensions from disk. `group` actions stay schema-only.
// Registration goes through the onRegister/onUnregister callbacks wired by ActionCoordinator;
// this file never touches ActionRegistry directly.
import Foundation




@MainActor
public final class ExtensionManager: Sendable {
    public static let shared = ExtensionManager()
    
    /// Wired by `ActionCoordinator.loadInitialState()`.
    public var onRegister: ((any Action) -> Void)?
    public var onUnregister: ((String) -> Void)?
    
    public private(set) var loadedActions: [any Action] = []
    public var actionFactory: (any ActionFactory)?
    public var optionWriter: (any ActionOptionWriting)?
    public var optionReader: (any ActionOptionReading)?
    
    /// Trust-gate persistence. When nil, gating is skipped; production sets it in AppDelegate.
    public var settingsStore: (any SettingsStore)?
    
    /// App version for `minOpenClipVersion` checks; overridable for tests.
    public var appVersionProvider: @Sendable () -> String = {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
    
    /// Trust events for the app target to surface as user notifications.
    public var onTrustChange: ((ExtensionTrustChange) -> Void)?
    
    private init() {}

    /// Returns the manager to its pristine state; test-isolation hook for the shared singleton.
    public func reset() {
        loadedActions = []
        onRegister = nil
        onUnregister = nil
        actionFactory = nil
        optionWriter = nil
        optionReader = nil
        settingsStore = nil
        onTrustChange = nil
    }
    
    public func loadExtensions(from url: URL = Constants.extensionsDirectory) async {
        let factory = self.actionFactory
        let scanned = await Task.detached {
            // Use the type name, not `Self`: `Self.X` in a Task.detached closure trips a Swift 6 isolation bug.
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
        
        // Register refreshed actions first so any transitioning actions (e.g. active <-> gated)
        // are already present in registeredActions before obsolete temporary IDs are unregistered.
        for action in finalActions {
            onRegister?(action)
        }
        let newIDs = Set(finalActions.map { $0.id })
        for oldAction in self.loadedActions where !newIDs.contains(oldAction.id) {
            onUnregister?(oldAction.id)
        }
        self.loadedActions = finalActions
    }
    
    /// Installs a package (.openclipext folder, .zip, or script file) into ~/.openclip/extensions.
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
            let folderName = sourceURL.lastPathComponent
            destinationURL = targetDir.appendingPathComponent(folderName)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)
        } else if sourceURL.pathExtension.lowercased() == "zip" {
            let stagingDir = targetDir.appendingPathComponent(".install_staging_\(UUID().uuidString)")
            
            // 1. Validate entries for containment BEFORE extraction to prevent Zip-Slip
            try await ExtensionManager.validateZipEntries(at: sourceURL, stagingDir: stagingDir)

            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stagingDir) }

            // Shared async runner, never waitUntilExit on the main actor; a non-zero exit throws here.
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
            let fileName = sourceURL.lastPathComponent
            destinationURL = targetDir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.copyItem(at: sourceURL, to: destinationURL)
        }
        
        // Return only this package's actions.
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

        // File packages default to source "package" unless one was recorded.
        if let installedPackageID {
            if let source {
                prepareInstall(source: source, packageID: installedPackageID)
            } else if self.settingsStore?.get(.extensionSources)[installedPackageID] == nil {
                prepareInstall(source: ExtensionSource.package.rawValue, packageID: installedPackageID)
            }
        }

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
    
    /// Seeds the source for `packageID` before a load, so store installs auto-trust during gating.
    public func prepareInstall(source: String, packageID: String) {
        guard let settings = self.settingsStore else { return }
        var sources = settings.get(.extensionSources)
        sources[packageID] = source
        settings.set(.extensionSources, value: sources)
    }

    public func setSource(_ source: String, for packageID: String) {
        guard let settings = self.settingsStore else { return }
        var sources = settings.get(.extensionSources)
        sources[packageID] = source
        settings.set(.extensionSources, value: sources)
    }
    
    /// Records the current content hash, marks the package trusted, and reloads. Fail-closed: persists
    /// nothing unless the fingerprint resolves.
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
    
    /// Marks the package revoked (explicit user "no"); reload swaps its actions for the gated placeholder.
    public func disablePackage(packageID: String, in directory: URL = Constants.extensionsDirectory) async {
        guard let settings = self.settingsStore else { return }
        var trust = settings.get(.extensionTrust)
        trust[packageID] = ExtensionTrustState.revoked.rawValue
        settings.set(.extensionTrust, value: trust)
        await loadExtensions(from: directory)
    }

    /// Re-records the fingerprint after an authorized in-app edit. Only `trusted` packages are re-trusted;
    /// `revoked` and never-enabled (`seen`) packages keep their state, since a save is not consent.
    public func retrustAfterAuthorizedEdit(packageID: String, in directory: URL = Constants.extensionsDirectory) async {
        guard let settings = self.settingsStore else { return }
        guard settings.get(.extensionTrust)[packageID] == ExtensionTrustState.trusted.rawValue else {
            await loadExtensions(from: directory)
            return
        }
        await enablePackage(packageID: packageID, in: directory)
    }
    
    /// Removes the extension's directory or file, matched by manifest identifier (the prefix of action IDs).
    public func uninstallExtension(actionID: String, targetDir: URL = Constants.extensionsDirectory) async throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey])
        // Prefer an exact manifest match over the prefix fallback, so uninstalling a copy can't remove the original.
        let exactPackageURL = items.first { itemURL in
            guard !itemURL.lastPathComponent.hasPrefix(".") else { return false }
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return false
            }
            return ExtensionManifestStore.candidateFileNames.contains { fileName in
                ExtensionManifestStore.readManifest(at: itemURL.appendingPathComponent(fileName))?.identifier == actionID
            }
        }
        let searchItems = exactPackageURL.map { exactURL in
            [exactURL] + items.filter { $0 != exactURL }
        } ?? items
        var removed = false
        var removedPackageID: String?

        for itemURL in searchItems {
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
                        // Match on a component boundary: com.foo must not match com.foobar.
                        let actionIDPrefix = meta.identifier + "."
                        let matchesIdentifier = actionID == meta.identifier || actionID.hasPrefix(actionIDPrefix)
                        // Also match a declared action id, so legacy un-namespaced packages stay removable.
                        let matchesAction = !matchesIdentifier && meta.actions.indices.contains { index in
                            ExtensionManager.uniformActionID(metadata: meta.actions[index], manifest: meta, index: index) == actionID
                        }
                        if matchesIdentifier || matchesAction {
                            matched = true
                            removedPackageID = meta.identifier
                            for (index, actionMeta) in meta.actions.enumerated() {
                                let id = ExtensionManager.uniformActionID(metadata: actionMeta, manifest: meta, index: index)
                                clearOptions(for: actionMeta, manifest: meta, actionID: id)
                            }
                        }
                        break
                    }
                }
            } else {
                // Match by the loader's exact id rules, never a filename substring: "a" is contained in "com.custom.alpha.sh".
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

    private func clearOptions(for metadata: ExtensionActionMetadata, manifest: ExtensionMetadata, actionID: String) {
        guard let optionWriter else { return }
        for option in (manifest.options ?? []) + (metadata.options ?? []) {
            optionWriter.clearValue(actionID: actionID, option: ExtensionOption(
                identifier: option.identifier,
                label: option.label,
                type: ExtensionOptionType(rawValue: option.type.lowercased()) ?? .string,
                defaultValue: option.defaultValue,
                options: option.values
            ))
        }
        guard metadata.kind == .group else { return }
        // Match the factory's group-relative IDs and its exclusion of nested groups.
        for (index, subAction) in (metadata.subActions ?? []).enumerated() where subAction.kind != .group {
            clearOptions(for: subAction, manifest: manifest, actionID: "\(actionID).\(subAction.id ?? String(index))")
        }
    }

    /// Clones an installed package under a unique copy id, copies its options, marks it trusted, and returns the new action ID.
    @discardableResult
    public func duplicateExtension(actionID: String, targetDir: URL = Constants.extensionsDirectory) async throws -> String {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.isDirectoryKey])
        let suffix = UUID().uuidString.prefix(6).lowercased()

        for itemURL in items {
            // Skip hidden/staging dirs
            guard !itemURL.lastPathComponent.hasPrefix(".") else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                for fname in ExtensionManifestStore.candidateFileNames {
                    let manifestURL = itemURL.appendingPathComponent(fname)
                    guard let manifest = ExtensionManifestStore.readManifest(at: manifestURL) else { continue }

                    let actionIDPrefix = manifest.identifier + "."
                    let matchesPackage = actionID == manifest.identifier || actionID.hasPrefix(actionIDPrefix)

                    var targetActionIndex: Int?
                    for (index, actionMeta) in manifest.actions.enumerated() {
                        let id = ExtensionManager.uniformActionID(metadata: actionMeta, manifest: manifest, index: index)
                        if id == actionID {
                            targetActionIndex = index
                            break
                        }
                    }

                    if matchesPackage || targetActionIndex != nil {
                        let newPackageID = "\(manifest.identifier).copy.\(suffix)"
                        let newDirName = "\(itemURL.lastPathComponent)-copy-\(suffix)"
                        let destinationDirURL = targetDir.appendingPathComponent(newDirName)

                        try fm.copyItem(at: itemURL, to: destinationDirURL)

                        let destManifestURL = destinationDirURL.appendingPathComponent(fname)
                        let newPackageName = "\(manifest.name) Copy"

                        var newActions = manifest.actions
                        for i in 0..<newActions.count {
                            let oldMeta = newActions[i]
                            let updatedID: String?
                            if let oldID = oldMeta.id {
                                if oldID.contains(".") {
                                    let tail = oldID.split(separator: ".").last.map(String.init) ?? oldID
                                    updatedID = "\(newPackageID).\(tail)"
                                } else {
                                    // Namespace the bare id under the new package. A dotted id would escape the package,
                                    // so uninstallExtension could never match it.
                                    updatedID = "\(newPackageID).\(oldID)"
                                }
                            } else {
                                updatedID = nil
                            }
                            let title = oldMeta.title.map { "\($0) Copy" } ?? newPackageName
                            newActions[i] = ExtensionActionMetadata(
                                id: updatedID,
                                title: title,
                                icon: oldMeta.icon,
                                script: oldMeta.script,
                                url: oldMeta.url,
                                regex: oldMeta.regex,
                                type: oldMeta.type,
                                scriptCode: oldMeta.scriptCode,
                                requirements: oldMeta.requirements,
                                isAsync: oldMeta.isAsync,
                                options: oldMeta.options,
                                subActions: oldMeta.subActions,
                                keyPress: oldMeta.keyPress,
                                serviceName: oldMeta.serviceName,
                                shortcutName: oldMeta.shortcutName,
                                menuRelevance: oldMeta.menuRelevance,
                                loading: oldMeta.loading,
                                loadingMessage: oldMeta.loadingMessage,
                                secondary: oldMeta.secondary,
                                toast: oldMeta.toast,
                                secondaryToast: oldMeta.secondaryToast,
                                keywords: oldMeta.keywords,
                                inline: oldMeta.inline,
                                localizedTitle: nil,
                                localizedLoadingMessage: oldMeta.localizedLoadingMessage,
                                output: oldMeta.output,
                                result: oldMeta.result
                            )
                        }

                        let updatedManifest = ExtensionMetadata(
                            identifier: newPackageID,
                            name: newPackageName,
                            actions: newActions,
                            options: manifest.options,
                            version: manifest.version,
                            capabilities: manifest.capabilities,
                            minOpenClipVersion: manifest.minOpenClipVersion,
                            keywords: manifest.keywords,
                            localizedName: nil,
                            description: manifest.description,
                            localizedDescription: manifest.localizedDescription,
                            author: manifest.author,
                            output: manifest.output,
                            result: manifest.result
                        )

                        try ExtensionManifestStore.writeManifest(updatedManifest, to: destManifestURL)

                        if let optionReader, let optionWriter {
                            for (index, actionMeta) in manifest.actions.enumerated() {
                                let oldActionID = ExtensionManager.uniformActionID(metadata: actionMeta, manifest: manifest, index: index)
                                let newActionID = ExtensionManager.uniformActionID(metadata: newActions[index], manifest: updatedManifest, index: index)
                                let allOptions = (manifest.options ?? []) + (actionMeta.options ?? [])
                                for optMeta in allOptions {
                                    let opt = ExtensionOption(
                                        identifier: optMeta.identifier,
                                        label: optMeta.label,
                                        type: ExtensionOptionType(rawValue: optMeta.type) ?? .string,
                                        defaultValue: optMeta.defaultValue,
                                        options: optMeta.values
                                    )
                                    let val = optionReader.stringValue(actionID: oldActionID, option: opt)
                                    if !val.isEmpty && val != (opt.defaultValue ?? "") {
                                        optionWriter.setStringValue(val, actionID: newActionID, option: opt)
                                    }
                                }
                            }
                        }

                        let currentHash = ExtensionPackageHashResolver.packageHash(manifestURL: destManifestURL, manifest: updatedManifest)
                        if let settings = self.settingsStore {
                            var sources = settings.get(.extensionSources)
                            sources[newPackageID] = "developer"
                            settings.set(.extensionSources, value: sources)

                            var trust = settings.get(.extensionTrust)
                            trust[newPackageID] = "trusted"
                            settings.set(.extensionTrust, value: trust)

                            if let currentHash {
                                var hashes = settings.get(.extensionTrustHashes)
                                hashes[newPackageID] = currentHash
                                settings.set(.extensionTrustHashes, value: hashes)
                            }
                        }

                        await loadExtensions(from: targetDir)

                        let targetIndex = targetActionIndex ?? 0
                        let matchingActionID = ExtensionManager.uniformActionID(
                            metadata: newActions[targetIndex],
                            manifest: updatedManifest,
                            index: targetIndex
                        )
                        return matchingActionID
                    }
                    break
                }
            } else {
                let synthesized = "\(Constants.customIdentifierPrefix)\(itemURL.lastPathComponent)"
                let declaredID = ExtensionPackageHashResolver.declaredIdentifier(of: itemURL)
                if actionID == synthesized || actionID == declaredID {
                    let ext = itemURL.pathExtension
                    let base = itemURL.deletingPathExtension().lastPathComponent
                    let newFileName = ext.isEmpty ? "\(base) Copy \(suffix)" : "\(base) Copy \(suffix).\(ext)"
                    let destinationURL = targetDir.appendingPathComponent(newFileName)

                    try fm.copyItem(at: itemURL, to: destinationURL)

                    let newPackageID = "\(Constants.customIdentifierPrefix)\(newFileName)"
                    let currentHash = ExtensionPackageHashResolver.fileHash(destinationURL)

                    if let settings = self.settingsStore {
                        var sources = settings.get(.extensionSources)
                        sources[newPackageID] = "developer"
                        settings.set(.extensionSources, value: sources)

                        var trust = settings.get(.extensionTrust)
                        trust[newPackageID] = "trusted"
                        settings.set(.extensionTrust, value: trust)

                        if let currentHash {
                            var hashes = settings.get(.extensionTrustHashes)
                            hashes[newPackageID] = currentHash
                            settings.set(.extensionTrustHashes, value: hashes)
                        }
                    }

                    await loadExtensions(from: targetDir)
                    return newPackageID
                }
            }
        }

        throw NSError(domain: "ExtensionManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No extension found for action \(actionID)."])
    }
    
    /// Test-only: raw scan results, bypassing trust gating.
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
                    // A manifest file marks a package; otherwise scan for standalone scripts.
                    let manifestFile = ExtensionManifestStore.manifestFileURL(in: itemURL)

                    if let manifestFile {
                        let actions = await loadManifestExtension(manifestURL: manifestFile, directoryURL: itemURL, factory: factory)
                        newActions.append(contentsOf: actions)
                    } else {
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

        // Unknown kinds, missing required fields, or unknown capabilities reject the whole package.
        let validator = ManifestValidator.shared
        let record = validator.validate(manifest, data: data)
        guard record.isValid else {
            let details = record.issues.map(\.description).joined(separator: "; ")
            Log.extensions.error("Extension manifest rejected at \(manifestURL.path, privacy: .public): \(details, privacy: .public)")
            return []
        }
        for warning in record.warnings {
            Log.extensions.warning("Extension manifest warning at \(manifestURL.path, privacy: .public): \(warning.description, privacy: .public)")
        }
        Log.extensions.notice("Loaded extension manifest \(manifest.identifier, privacy: .public) (v\(record.declaredVersion ?? "-", privacy: .public), schema \(record.schemaVersion, privacy: .public), \(manifest.actions.count) action(s), sha256 \(record.fingerprint, privacy: .public))")

        var actions: [any Action] = []
        for (index, actionMeta) in manifest.actions.enumerated() {
            if let factory {
                // `.group` entries flatten into a GroupAction row plus sub-actions.
                actions.append(contentsOf: await factory.createActions(metadata: actionMeta, manifest: manifest, directoryURL: directoryURL, index: index))
            } else if actionMeta.kind != .group {
                let actionId = uniformActionID(metadata: actionMeta, manifest: manifest, index: index)
                let title = actionMeta.title ?? manifest.name
                let icon = parseIcon(actionMeta.icon, directoryURL: directoryURL)
                let regex = actionMeta.regex
                // Stamp the package id as chrome.source (not the action id) so the trust gate groups by package.
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
        ActionIcon.resolve(from: iconStr, relativeTo: directoryURL)
    }

    /// Explicit `metadata.id` wins (bare slugs get the package prefix); else `<identifier>.action.<index>`.
    nonisolated public static func uniformActionID(metadata: ExtensionActionMetadata, manifest: ExtensionMetadata, index: Int) -> String {
        if let id = metadata.id {
            return id.contains(".") ? id : "\(manifest.identifier).\(id)"
        }
        return "\(manifest.identifier).action.\(index)"
    }

    /// Validates zip entry paths (`unzip -Z1`) before extraction, against Zip-Slip.
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

        // Reject symlink entries: a later entry could follow one to write outside stagingDir.
        let verboseOutput = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-Z", "-v", zipURL.path],
            environment: [:]
        ))
        if let symlinkName = firstSymlinkEntry(in: verboseOutput.stdout) {
            throw NSError(domain: "ExtensionManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Archive contains a symbolic-link entry: \(symlinkName)"])
        }
    }

    /// First symlink entry (S_IFLNK in the Unix mode bits) in `unzip -Z -v` output.
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
