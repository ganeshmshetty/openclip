import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    public init() {}

    public func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL
    ) async -> (any Action)? {
        let actionId = "\(manifest.identifier).action.\(metadata.title ?? manifest.name)"
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
        
        if let urlTemplate = metadata.url {
            return URLTemplateAction(
                id: actionId,
                title: title,
                icon: icon,
                urlTemplate: urlTemplate,
                regexPattern: metadata.regex
            )
        }
        
        let scriptName = metadata.script ?? Constants.defaultScriptName
        let scriptURL = directoryURL.appendingPathComponent(scriptName)
        let ext = scriptURL.pathExtension.lowercased()
        
        switch ext {
        case "js":
            let code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
            return JavaScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptCode: code,
                options: options
            )
        case "applescript", "scpt":
            let code = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
            return AppleScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                appleScriptCode: code,
                options: options
            )
        default:
            return ScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptURL: scriptURL
            )
        }
    }
}
