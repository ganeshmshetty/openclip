// OpenClipSnippetParser.swift
// OpenClip
//
// Parses OpenClip script snippet headers into extension and action metadata structures without UI dependencies.
// Note: currently annotated @MainActor; making it fully nonisolated is planned.
import Foundation

@MainActor
public struct OpenClipSnippetParser: Sendable {
    public static func parseSnippetMetadata(snippet: String) -> (manifest: ExtensionMetadata, actionMetadata: ExtensionActionMetadata)? {
        let lines = snippet.components(separatedBy: .newlines)
        
        let knownKeys = ["title", "name", "icon", "identifier", "id", "url", "javascript", "js", "applescript", "shell script", "sh", "shell"]
        
        // A snippet must actually look like an OpenClip header: either the #openclip/`//openclip`
        // marker or a recognized key line (e.g. `# Title: Foo`). A bare `#`/`//` comment is not enough.
        let isHeaderPresent = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasPrefix("#openclip") || trimmed.hasPrefix("//openclip") { return true }
            var stripped = trimmed
            if stripped.hasPrefix("//") {
                stripped = String(stripped.dropFirst(2))
            } else if stripped.hasPrefix("#") {
                stripped = String(stripped.dropFirst(1))
            }
            stripped = stripped.trimmingCharacters(in: .whitespaces)
            let key = stripped.split(separator: ":").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            return !key.isEmpty && knownKeys.contains(key)
        }
        guard isHeaderPresent else { return nil }
        
        var dict: [String: String] = [:]
        var bodyDict: [String: [String]] = [:]
        var activeBodyKey: String? = nil
        
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // In body mode, only a `#`-prefixed recognized header key closes the body and starts a new
            // header line; `//`-prefixed lines and everything else stay body content (e.g. JS comments,
            // URLs with fragments). This lets a later `# Icon:` header survive after a `js:`/`url:` body.
            if let key = activeBodyKey {
                var closesBody = false
                if trimmed.hasPrefix("#") {
                    let stripped = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                    let parts = stripped.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    let candidateKey = parts.first?.lowercased() ?? ""
                    if parts.count == 2 && knownKeys.contains(candidateKey) {
                        closesBody = true
                    }
                }
                if !closesBody {
                    bodyDict[key, default: []].append(line)
                    continue
                }
                activeBodyKey = nil
            }
            
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
                }
            } else if parts.count == 1 && knownKeys.contains(candidateKey) && line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                let key = candidateKey
                dict[key] = ""
                activeBodyKey = key
            }
        }
        
        guard let title = dict["title"] ?? dict["name"], !title.isEmpty else { return nil }
        
        let slug = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: ".")
        let id = dict["identifier"] ?? dict["id"] ?? "snippet.\(slug)"
        let rawIcon = dict["icon"] ?? "sparkles"
        
        var urlValue: String? = nil
        var actionType: String? = nil
        var scriptCodeValue: String? = nil
        
        // 1. URL template action
        if let urlVal = dict["url"], !urlVal.isEmpty {
            let body = bodyDict["url"]?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            urlValue = body.isEmpty ? urlVal : urlVal + "\n" + body
        } else if let bodyLines = bodyDict["url"], !bodyLines.isEmpty {
            urlValue = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Native JavaScript action
        if urlValue == nil {
            let jsKey = dict.keys.contains("javascript") ? "javascript" : (dict.keys.contains("js") ? "js" : nil)
            if let key = jsKey {
                let inlineVal = dict[key] ?? ""
                let bodyLines = bodyDict[key] ?? []
                scriptCodeValue = (bodyLines.isEmpty ? inlineVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
                actionType = "javascript"
            }
        }
        
        // 3. Native AppleScript action
        if urlValue == nil && scriptCodeValue == nil {
            if let appleVal = dict["applescript"] {
                let bodyLines = bodyDict["applescript"] ?? []
                scriptCodeValue = (bodyLines.isEmpty ? appleVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
                actionType = "applescript"
            }
        }
        
        // 4. Shell script action
        if urlValue == nil && scriptCodeValue == nil {
            let shKey = dict.keys.contains("shell script") ? "shell script" : (dict.keys.contains("sh") ? "sh" : (dict.keys.contains("shell") ? "shell" : nil))
            if let key = shKey {
                let inlineVal = dict[key] ?? ""
                let bodyLines = bodyDict[key] ?? []
                scriptCodeValue = (bodyLines.isEmpty ? inlineVal : bodyLines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
                actionType = "shell"
            }
        }
        
        guard urlValue != nil || scriptCodeValue != nil else { return nil }
        
        let actionMeta = ExtensionActionMetadata(
            id: id,
            title: title,
            icon: rawIcon,
            script: nil,
            url: urlValue,
            regex: nil,
            type: actionType,
            scriptCode: scriptCodeValue
        )
        
        let manifest = ExtensionMetadata(
            identifier: id,
            name: title,
            actions: [actionMeta],
            options: nil
        )
        
        return (manifest, actionMeta)
    }

    public static func parse(
        snippet: String,
        factory: (any ActionFactory)? = nil,
        directoryURL: URL = URL(fileURLWithPath: "/tmp")
    ) async -> (any Action)? {
        guard let (manifest, actionMeta) = parseSnippetMetadata(snippet: snippet) else {
            return nil
        }
        
        if let factory = factory, let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: directoryURL) {
            return action
        }
        
        let actionId = actionMeta.id ?? manifest.identifier
        let title = manifest.name
        let rawIcon = actionMeta.icon ?? "sparkles"
        let iconSymbol = rawIcon.hasPrefix("symbol:") ? String(rawIcon.dropFirst(7)) : rawIcon
        
        if let urlTemplate = actionMeta.url {
            return URLTemplateAction(id: actionId, title: title, icon: .symbol(iconSymbol), urlTemplate: urlTemplate)
        }
        
        if actionMeta.type == "shell", let scriptCode = actionMeta.scriptCode {
            return CustomAction(
                id: actionId,
                title: title,
                iconName: iconSymbol,
                type: .shellScript(script: scriptCode, replaceSelection: true)
            )
        }
        
        return nil
    }
}
