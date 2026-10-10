// RevealInFinderAction.swift
// OpenClip
//
// Implements Finder file reveal actions for file paths found in selected text using NSWorkspace.
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct RevealInFinderAction: ConfigurableAction {
    public let id = "builtin.reveal_in_finder"
    public var title: String { String(localized: "Reveal in Finder") }
    public let icon = ActionIcon.symbol("folder")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return resolvePath(from: context.selection.text, detected: context.selection.detectedContent(for: [.path]).paths) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        guard let path = resolvePath(from: context.selection.text, detected: context.selection.detectedContent(for: [.path]).paths) else {
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
        resolvePath(from: text, detected: NativeContentDetector.paths(in: text))
    }

    private func resolvePath(from text: String, detected: [String]) -> String? {
        // Preserve direct selections containing unquoted spaces and literal punctuation.
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let direct = (raw as NSString).expandingTildeInPath
        if direct.hasPrefix("/"), FileManager.default.fileExists(atPath: direct) { return direct }
        if let path = NativeContentDetector.normalizedPath(raw), FileManager.default.fileExists(atPath: path) {
            return path
        }
        return firstExistingPath(detected)
    }

    private func firstExistingPath(_ paths: [String]) -> String? {
        // Filesystem probes remain bounded and outside the pure detection layer.
        paths.prefix(5).first { FileManager.default.fileExists(atPath: $0) }
    }
}
