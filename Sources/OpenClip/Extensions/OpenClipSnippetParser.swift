import Foundation
import Core

@MainActor
public struct OpenClipSnippetParser {
    public static func parse(snippet: String) -> (any Action)? {
        let lines = snippet.components(separatedBy: .newlines)
        let isHeaderPresent = lines.contains(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.hasPrefix("#openclip") || trimmed.hasPrefix("//openclip") || trimmed.hasPrefix("#popclip")
        })
        guard isHeaderPresent else { return nil }
        
        var dict: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                dict[parts[0].lowercased()] = parts[1]
            }
        }
        
        guard let title = dict["title"] ?? dict["name"] else { return nil }
        let id = dict["identifier"] ?? "snippet.\(UUID().uuidString)"
        let iconSymbol = dict["icon"] ?? "sparkles"
        
        if let urlTemplate = dict["url"] {
            return URLTemplateAction(id: id, title: title, icon: .symbol(iconSymbol), urlTemplate: urlTemplate)
        }
        
        if let jsCode = dict["javascript"] ?? dict["js"] {
            return JavaScriptAction(id: id, title: title, iconSymbol: iconSymbol, scriptCode: jsCode)
        }
        
        if let appleScript = dict["applescript"] {
            return AppleScriptAction(id: id, title: title, iconSymbol: iconSymbol, appleScriptCode: appleScript)
        }
        
        if let shellScript = dict["shell script"] ?? dict["sh"] {
            return CustomAction(
                id: id,
                title: title,
                iconName: iconSymbol,
                type: .shellScript(script: shellScript, replaceSelection: true)
            )
        }
        
        return nil
    }
}
