// DefaultActionFactory.swift
// OpenClip
//
// Serves as the Birth Door implementation, instantiating executable Action instances from extension manifests and snippets.
// Applies the uniform action-ID rule, keeps `group` actions schema-only (returns nil in Phase 1), and threads the
// option store into every runtime that reads configured option values.
import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    private let optionStore: any ActionOptionReading

    public init(optionStore: any ActionOptionReading = SettingsActionOptionStore()) {
        self.optionStore = optionStore
    }

    /// Maps manifest/action option metadata to the runtime `ExtensionOption` model, wiring
    /// `values`/`options` into the `.multiple` picker choices (T1-minor-1 carryover).
    private func makeExtensionOption(from metadata: ExtensionOptionMetadata) -> ExtensionOption {
        ExtensionOption(
            identifier: metadata.identifier,
            label: metadata.label,
            type: ExtensionOptionType(rawValue: metadata.type.lowercased()) ?? .string,
            defaultValue: metadata.defaultValue,
            options: metadata.values
        )
    }

    /// Merges per-action option overrides (`metadata.options`) onto the manifest-level defaults
    /// (`manifest.options`) by identifier. Manifest-level options keep their order; overrides
    /// replace matching identifiers in place, and identifiers unique to the action are appended
    /// in declaration order.
    private func mergedOptions(
        manifestOptions: [ExtensionOptionMetadata]?,
        actionOptions: [ExtensionOptionMetadata]?
    ) -> [ExtensionOption] {
        var result: [ExtensionOption] = (manifestOptions ?? []).map(makeExtensionOption)
        guard let actionOverrides = actionOptions, !actionOverrides.isEmpty else { return result }

        var overrides: [String: ExtensionOption] = [:]
        var orderedNewKeys: [String] = []
        for metadata in actionOverrides {
            let option = makeExtensionOption(from: metadata)
            if overrides[option.identifier] == nil { orderedNewKeys.append(option.identifier) }
            overrides[option.identifier] = option
        }
        for index in result.indices {
            if let override = overrides[result[index].identifier] {
                result[index] = override
                overrides.removeValue(forKey: result[index].identifier)
                orderedNewKeys.removeAll { $0 == result[index].identifier }
            }
        }
        for key in orderedNewKeys {
            if let override = overrides[key] {
                result.append(override)
            }
        }
        return result
    }

    public func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> (any Action)? {
        // Groups are schema-only in Phase 1 (runtimes land in Phase 8): never register a group as runnable.
        guard metadata.kind != .group else { return nil }
        let actionId = ExtensionManager.uniformActionID(metadata: metadata, manifest: manifest, index: index)
        let title = metadata.title ?? manifest.name
        let icon = ExtensionManager.parseIcon(metadata.icon, directoryURL: directoryURL)
        
        let options = mergedOptions(manifestOptions: manifest.options, actionOptions: metadata.options)
        
        // Declarative visibility/behavior rules applied to every extension action this factory
        // creates: requirements (regex, app allow/deny, requiresSelection) + legacy manifest
        // `regex` + after-run behavior + stay-visible.
        let rules = ExtensionActionRules(
            requirements: metadata.requirements,
            legacyRegex: metadata.regex,
            after: metadata.after ?? .default,
            stayVisible: metadata.stayVisible ?? false
        )
        
        let extensionChrome = ActionChrome(
            badge: .extensionPkg(manifest.name),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: manifest.identifier)
        )
        
        if let urlTemplate = metadata.url {
            return URLTemplateAction(
                id: actionId,
                title: title,
                icon: icon,
                urlTemplate: urlTemplate,
                regexPattern: metadata.regex,
                chrome: extensionChrome,
                rules: rules
            )
        }
        
        if let scriptCode = metadata.scriptCode, !scriptCode.isEmpty {
            let typeStr = (metadata.type ?? "").lowercased()
            switch typeStr {
            case "js", "javascript":
                return JavaScriptAction(
                    id: actionId,
                    title: title,
                    icon: icon,
                    scriptCode: scriptCode,
                    options: options,
                    chrome: extensionChrome,
                    optionStore: optionStore,
                    rules: rules
                )
            case "applescript", "scpt":
                return AppleScriptAction(
                    id: actionId,
                    title: title,
                    icon: icon,
                    appleScriptCode: scriptCode,
                    options: options,
                    chrome: extensionChrome,
                    rules: rules
                )
            case "sh", "shell", "shell script":
                let iconSymbol = switch icon {
                case .symbol(let name): name
                case .local(let url): url.lastPathComponent
                case .url(let url): url.absoluteString
                case .text(let txt): txt
                }
                return CustomAction(
                    id: actionId,
                    title: title,
                    iconName: iconSymbol,
                    type: .shellScript(script: scriptCode, replaceSelection: true),
                    rules: rules
                )
            default:
                break
            }
        }
        
        let scriptName = metadata.script ?? Constants.defaultScriptName
        let scriptURL = directoryURL.appendingPathComponent(scriptName)
        let ext = scriptURL.pathExtension.lowercased()

        // Guard against garbage metadata: with neither url, scriptCode, nor an existing script file,
        // there is nothing executable to run. A directory (fileExists is true for directories) or a
        // script that can't be read must not register as an empty action.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        switch ext {
        case "js":
            guard let code = try? String(contentsOf: scriptURL, encoding: .utf8), !code.isEmpty else { return nil }
            return JavaScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptCode: code,
                options: options,
                chrome: extensionChrome,
                optionStore: optionStore,
                rules: rules
            )
        case "applescript", "scpt":
            guard let code = try? String(contentsOf: scriptURL, encoding: .utf8), !code.isEmpty else { return nil }
            return AppleScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                appleScriptCode: code,
                options: options,
                chrome: extensionChrome,
                rules: rules
            )
        default:
            return ScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptURL: scriptURL,
                chrome: extensionChrome,
                rules: rules
            )
        }
    }
}
