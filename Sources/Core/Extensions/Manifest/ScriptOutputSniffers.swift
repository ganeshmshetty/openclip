// ScriptOutputSniffers.swift
// OpenClip
//
// Heuristic sniffers for script content (JS, AppleScript, Shell) used as an inference bridge
// for legacy extensions that do not declare an explicit `output` contract in their manifest.
import Foundation

public enum ScriptOutputSniffers {
    /// Determines if a JavaScript extension produces text output governed by the delivery preference.
    public static func jsProducesText(code: String) -> Bool {
        // 1. Check for arrow function with direct expression body (e.g. `const action = (text) => text.trim()`):
        let arrowExprPattern = #"(?:(?:var|let|const)\s+)?(?:action|main)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[a-zA-Z0-9_]+)\s*=>\s*([^{\s\n;][^;\n]*)"#
        if let match = code.range(of: arrowExprPattern, options: .regularExpression) {
            let matchedStr = String(code[match])
            // If the arrow expression evaluates to a non-text literal like void/undefined/null/boolean:
            if matchedStr.range(of: #"=>\s*(?:undefined|null|true|false)\b"#, options: .regularExpression) == nil {
                return true
            }
            return false
        }

        // 2. Look for action/main entry function with block body:
        let entryHeaderPattern = #"(?:(?:async\s+)?function\s+(?:action|main)\s*\([^)]*\)|(?:(?:var|let|const)\s+)?(?:action|main)\s*=\s*(?:async\s*)?(?:function\s*\([^)]*\)|\([^)]*\)\s*=>|[a-zA-Z0-9_]+\s*=>))\s*\{"#
        if let match = code.range(of: entryHeaderPattern, options: .regularExpression) {
            let openBraceIndex = code.index(before: match.upperBound)
            if let body = extractBracedBlock(from: code, openBrace: openBraceIndex) {
                return bodyHasReturnText(body)
            }
        }

        // Fallback: check whole script if no formal action/main entry function was found
        return bodyHasReturnText(code)
    }

    private static func bodyHasReturnText(_ body: String) -> Bool {
        body.range(of: #"return\s+(?!(?:true|false|undefined|null)\b)[^;}\s]"#, options: .regularExpression) != nil
    }

    private static func extractBracedBlock(from text: String, openBrace: String.Index) -> String? {
        guard openBrace < text.endIndex, text[openBrace] == "{" else { return nil }
        var depth = 0
        var currentIndex = openBrace
        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[openBrace...currentIndex])
                }
            }
            currentIndex = text.index(after: currentIndex)
        }
        return String(text[openBrace...])
    }

    /// Determines if an AppleScript extension produces text output.
    public static func appleScriptProducesText(code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        // Explicit non-empty return produces text regardless of preceding side-effects
        let hasExplicitReturn = trimmed.range(of: #"return\s+(?!\s*["']["']|missing value\b)\S+"#, options: .regularExpression) != nil
        if hasExplicitReturn {
            return true
        }

        // Explicit empty return produces no text
        if trimmed.contains("return \"\"") || trimmed.contains("return ''") || trimmed.contains("return missing value") {
            return false
        }

        if trimmed.hasPrefix("say ") { return false }
        if trimmed.contains("tell application \"System Events\"") && trimmed.contains("keystroke") {
            return false
        }
        if trimmed.contains("do shell script") && trimmed.contains("main.sh") {
            return false
        }
        return true
    }

    /// Determines if a shell extension produces text output to stdout.
    public static func shellProducesText(code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        // QuickLook preview window (e.g. qlmanage -p in QR Code Generator)
        if let qlRange = trimmed.range(of: "qlmanage") {
            let after = String(trimmed[qlRange.upperBound...])
            if !hasStdoutProducer(after) && !hasStdoutProducer(trimmed) {
                return false
            }
        }

        // Background process with output redirected to /dev/null and no stdout
        if (trimmed.contains(">/dev/null") || trimmed.contains("> /dev/null")) && trimmed.contains("&") {
            if !hasStdoutProducer(trimmed) {
                return false
            }
        }

        // Swift / Cocoa GUI runner or binary with no stdout (e.g. Large Type)
        if let guiRange = trimmed.range(of: #"(?:swift\s+|main\.swift|largetype)"#, options: .regularExpression) {
            let after = String(trimmed[guiRange.upperBound...])
            if !hasStdoutProducer(after) && !hasStdoutProducer(trimmed) {
                return false
            }
        }

        // Piping into `open` (e.g. `printf ... | open -f -a TextEdit`) or bare `open -a`
        if trimmed.contains("| open ") || trimmed.contains("| /usr/bin/open ") {
            return false
        }

        // Opens an application without producing text
        if trimmed.contains("open -a ") || trimmed.contains("open -f ") || trimmed.contains("open -g ") {
            if !hasStdoutProducer(trimmed) {
                return false
            }
        }

        // Emits only JSON toast effects (like Harper check/dictionary/forget)
        if trimmed.contains("{\"type\":\"toast\"") || trimmed.contains("{type:\"toast\"") {
            if !trimmed.contains("| implode") && !trimmed.contains("type:\"copy\"") {
                return false
            }
        }

        return true
    }

    private static func hasStdoutProducer(_ text: String) -> Bool {
        let patterns = [
            #"echo\s"#,
            #"printf\s"#,
            #"cat\s"#,
            #"cat$"#,
            #"\|\s*implode"#,
            #"type:\"copy\""#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
