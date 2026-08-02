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
    public let title = "Reveal in Finder"
    public let icon = ActionIcon.symbol("folder")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let path = resolvePath(from: context.selection.text) else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard let path = resolvePath(from: context.selection.text) else {
            return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
        }
        
        #if canImport(AppKit)
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        return .success
        #else
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
        #endif
    }
    
    public func resolvePath(from text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        
        if trimmed.isEmpty { return nil }
        
        if trimmed.hasPrefix("file://") {
            if let url = URL(string: trimmed) {
                return url.path
            }
        }
        
        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") && FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }
        
        return nil
    }
}
