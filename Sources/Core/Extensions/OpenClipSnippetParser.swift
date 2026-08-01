import Foundation

@MainActor
public struct OpenClipSnippetParser: Sendable {
    public static func parse(snippet: String) -> (any Action)? {
        let lines = snippet.components(separatedBy: .newlines)
        
        let isHeaderPresent = lines.contains(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.hasPrefix("#openclip") || trimmed.hasPrefix("//openclip") || trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
        })
        guard isHeaderPresent else { return nil }
        
        var dict: [String: String] = [:]
        var bodyDict: [String: [String]] = [:]
        var activeBodyKey: String? = nil
        
        let knownKeys = ["title", "name", "icon", "identifier", "id", "url", "javascript", "js", "applescript", "shell script", "sh", "shell"]
        
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") {
                trimmed = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("#") {
                trimmed = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            }
            
            if trimmed.lowercased().hasPrefix("openclip") {
                continue
            }
            
            let parts = trimmed.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            let candidateKey = parts.first?.lowercased() ?? ""
            
            if parts.count == 2 && knownKeys.contains(candidateKey) {
                let key = candidateKey
                let val = parts[1]
                dict[key] = val
                if ["url", "javascript", "js", "applescript", "shell script", "sh", "shell"].contains(key) {
                    activeBodyKey = key
                    if !val.isEmpty {
                        bodyDict[key, default: []].append(val)
                    }
                } else {
                    activeBodyKey = nil
                }
            } else if parts.count == 1 && knownKeys.contains(candidateKey) && line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                let key = candidateKey
                dict[key] = ""
                activeBodyKey = key
            } else if let key = activeBodyKey {
                bodyDict[key, default: []].append(line)
            }
        }
        
        guard let title = dict["title"] ?? dict["name"], !title.isEmpty else { return nil }
        
        let slug = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: ".")
        let id = dict["identifier"] ?? dict["id"] ?? "snippet.\(slug)"
        
        let rawIcon = dict["icon"] ?? "sparkles"
        let iconSymbol = rawIcon.hasPrefix("symbol:") ? String(rawIcon.dropFirst(7)) : rawIcon
        
        // 1. URL template action
        if let urlVal = dict["url"], !urlVal.isEmpty {
            let body = bodyDict["url"]?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fullURL = body.isEmpty ? urlVal : urlVal + "\n" + body
            return URLTemplateAction(id: id, title: title, icon: .symbol(iconSymbol), urlTemplate: fullURL)
        } else if let bodyLines = bodyDict["url"], !bodyLines.isEmpty {
            let fullURL = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return URLTemplateAction(id: id, title: title, icon: .symbol(iconSymbol), urlTemplate: fullURL)
        }
        
        // 2. Native JavaScript action
        let jsKey = dict.keys.contains("javascript") ? "javascript" : (dict.keys.contains("js") ? "js" : nil)
        if let key = jsKey {
            let inlineVal = dict[key] ?? ""
            let bodyLines = bodyDict[key] ?? []
            let fullCode = (bodyLines.isEmpty ? inlineVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            return JavaScriptAction(id: id, title: title, iconSymbol: iconSymbol, scriptCode: fullCode)
        }
        
        // 3. Native AppleScript action
        if let appleVal = dict["applescript"] {
            let bodyLines = bodyDict["applescript"] ?? []
            let fullCode = (bodyLines.isEmpty ? appleVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            return AppleScriptAction(id: id, title: title, iconSymbol: iconSymbol, appleScriptCode: fullCode)
        }
        
        // 4. Shell script action
        let shKey = dict.keys.contains("shell script") ? "shell script" : (dict.keys.contains("sh") ? "sh" : (dict.keys.contains("shell") ? "shell" : nil))
        if let key = shKey {
            let inlineVal = dict[key] ?? ""
            let bodyLines = bodyDict[key] ?? []
            let fullCode = (bodyLines.isEmpty ? inlineVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            return CustomAction(
                id: id,
                title: title,
                iconName: iconSymbol,
                type: .shellScript(script: fullCode, replaceSelection: true)
            )
        }
        
        return nil
    }
}
