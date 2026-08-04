// DefaultActionFactory.swift
// OpenClip
//
// Serves as the Birth Door implementation, instantiating executable Action instances from extension manifests and snippets.
// Applies the uniform action-ID rule and keeps `group` actions schema-only (returns nil in Phase 1).
import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    public init() {}

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
        
        let options = manifest.options?.map { opt -> ExtensionOption in
            let optType = ExtensionOptionType(rawValue: opt.type.lowercased()) ?? .string
            return ExtensionOption(
                identifier: opt.identifier,
                label: opt.label,
                type: optType,
                defaultValue: opt.defaultValue
            )
        } ?? []
        
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
                chrome: extensionChrome
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
                    chrome: extensionChrome
                )
            case "applescript", "scpt":
                return AppleScriptAction(
                    id: actionId,
                    title: title,
                    icon: icon,
                    appleScriptCode: scriptCode,
                    options: options,
                    chrome: extensionChrome
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
                    type: .shellScript(script: scriptCode, replaceSelection: true)
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
                chrome: extensionChrome
            )
        case "applescript", "scpt":
            guard let code = try? String(contentsOf: scriptURL, encoding: .utf8), !code.isEmpty else { return nil }
            return AppleScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                appleScriptCode: code,
                options: options,
                chrome: extensionChrome
            )
        default:
            return ScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptURL: scriptURL,
                chrome: extensionChrome
            )
        }
    }
}
