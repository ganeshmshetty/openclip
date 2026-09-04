// RevealInFinderAction.swift
// OpenClip
//
// Implements Finder file reveal actions for file paths found in selected text using NSWorkspace.
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct RevealInFinderAction: Action {
    public let id = "builtin.reveal_in_finder"
    public var title: String { String(localized: "Reveal in Finder") }
    public let icon = ActionIcon.symbol("folder")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return resolvePath(from: context.selection.text) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard let path = resolvePath(from: context.selection.text) else {
            return .failure(NSError(
                domain: Constants.actionErrorDomain,
                code: Constants.actionErrorCode,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "No existing file path found in selection.")]
            ))
        }
        
        #if canImport(AppKit)
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        return .success
        #else
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
        #endif
    }
    
    public func resolvePath(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Fast path 1: Check entire selection directly
        if let directPath = checkSinglePath(trimmed) {
            return directPath
        }
        
        // Fast path 2: Instant bailout if no path indicators exist (0 filesystem stat calls)
        guard trimmed.contains("/") || trimmed.contains("~") else { return nil }
        
        // Fallback: Scan token candidates (capped at 5 to prevent UI stalls on massive text)
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var checksPerformed = 0
        let maxCandidateChecks = 5
        
        for token in tokens {
            guard checksPerformed < maxCandidateChecks else { break }
            
            let cleaned = stripDelimiters(token)
            guard cleaned.hasPrefix("/") || cleaned.hasPrefix("~") || cleaned.hasPrefix("file://") else {
                continue
            }
            
            checksPerformed += 1
            if let resolved = checkSinglePath(cleaned) {
                return resolved
            }
        }
        
        return nil
    }
    
    private func checkSinglePath(_ rawPath: String) -> String? {
        var path = stripDelimiters(rawPath)
        guard !path.isEmpty else { return nil }
        
        // Handle file:// URIs
        if path.hasPrefix("file://") {
            if let url = URL(string: path) {
                path = url.path
            } else {
                path = String(path.dropFirst(7))
            }
        }
        
        // Unescape shell spaces: "\ " -> " "
        let unescaped = path.replacingOccurrences(of: "\\ ", with: " ")
        
        // Step A: Direct expansion (fastest, exact match)
        let expanded = (unescaped as NSString).expandingTildeInPath
        if isExistingPath(expanded) {
            return expanded
        }
        
        // Step B: Strip trailing line/column (:80:15) and sentence punctuation (. , ;)
        let stripped = stripLineNumbersAndPunctuation(expanded)
        let cleaned = stripDelimiters(stripped)
        let cleanedExpanded = (cleaned as NSString).expandingTildeInPath
        if isExistingPath(cleanedExpanded) {
            return cleanedExpanded
        }
        
        return nil
    }
    
    private func isExistingPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func stripDelimiters(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(String, String)] = [
            ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"),
            ("<", ">"), ("(", ")"), ("[", "]")
        ]
        for (lead, trail) in wrappers {
            if s.hasPrefix(lead) && s.hasSuffix(trail) && s.count >= (lead.count + trail.count) {
                s = String(s.dropFirst(lead.count).dropLast(trail.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let leadingWrappers = CharacterSet(charactersIn: "\"‘“'<([")
        while let first = s.unicodeScalars.first, leadingWrappers.contains(first) {
            s.removeFirst()
        }
        let trailingWrappers = CharacterSet(charactersIn: "\"'”’)>]")
        while let last = s.unicodeScalars.last, trailingWrappers.contains(last) {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func stripLineNumbersAndPunctuation(_ raw: String) -> String {
        var s = raw
        // 1. Strip trailing sentence punctuation
        let trailingChars = CharacterSet(charactersIn: ".,;:!?\"'”’)]>")
        while let last = s.unicodeScalars.last, trailingChars.contains(last) {
            s.removeLast()
        }
        
        // 2. Strip compiler location suffix: :line:col or :line (e.g. :80:15 or :80)
        if let lastColon = s.lastIndex(of: ":") {
            let suffix = String(s[lastColon...])
            if suffix.count > 1 && suffix.dropFirst().allSatisfy({ $0.isNumber }) {
                s = String(s[..<lastColon])
                if let secondColon = s.lastIndex(of: ":") {
                    let secondSuffix = String(s[secondColon...])
                    if secondSuffix.count > 1 && secondSuffix.dropFirst().allSatisfy({ $0.isNumber }) {
                        s = String(s[..<secondColon])
                    }
                }
            }
        }
        return s
    }
}
