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
        
        // 1. Open URL Actions
        if let urlTemplate = dict["url"] {
            return URLTemplateAction(id: id, title: title, icon: .symbol(iconSymbol), urlTemplate: urlTemplate)
        }
        
        // 2. JavaScript Actions
        if let jsCode = dict["javascript"] ?? dict["js"] {
            return JavaScriptAction(id: id, title: title, iconSymbol: iconSymbol, scriptCode: jsCode)
        }
        
        // 3. AppleScript Actions
        if let appleScript = dict["applescript"] {
            return AppleScriptAction(id: id, title: title, iconSymbol: iconSymbol, appleScriptCode: appleScript)
        }
        
        // 4. Shell Script Actions
        if let shellScript = dict["shell script"] ?? dict["sh"] {
            return CustomAction(
                id: id,
                title: title,
                iconName: iconSymbol,
                type: .shellScript(script: shellScript, replaceSelection: true)
            )
        }
        
        // 5. Shortcut Actions
        if let shortcutName = dict["shortcut name"] ?? dict["shortcut"] {
            return ShortcutAction(id: id, title: title, iconSymbol: iconSymbol, shortcutName: shortcutName)
        }
        
        // 6. Service Actions
        if let serviceName = dict["service name"] ?? dict["service"] {
            return ServiceAction(id: id, title: title, iconSymbol: iconSymbol, serviceName: serviceName)
        }
        
        // 7. KeyCombo Actions
        if let _ = dict["key combo"] ?? dict["key code"] {
            return KeyComboAction(id: id, title: title, iconSymbol: iconSymbol, keyCode: 0x08, modifiers: [.maskCommand])
        }
        
        return nil
    }
}
