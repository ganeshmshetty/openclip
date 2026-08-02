// DefaultActionFactory.swift
// OpenClip
//
// Serves as the Birth Door implementation, instantiating executable Action instances from extension manifests and snippets.
import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    public init() {}

    public func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL
    ) async -> (any Action)? {
        let actionId = metadata.id ?? (manifest.identifier.hasPrefix("snippet.") ? manifest.identifier : "\(manifest.identifier).action.\(metadata.title ?? manifest.name)")
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
        // there is nothing executable to run.
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return nil }
        
        switch ext {
        case "js":
            let code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
            return JavaScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptCode: code,
                options: options,
                chrome: extensionChrome
            )
        case "applescript", "scpt":
            let code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
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
