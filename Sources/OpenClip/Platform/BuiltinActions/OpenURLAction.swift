// OpenURLAction.swift
// OpenClip
//
// Implements URL opening actions using macOS NSWorkspace workspace services.
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct OpenURLAction: ConfigurableAction {
    public let id = "builtin.openurl"
    public var title: String { String(localized: "Open Link") }
    public let icon = ActionIcon.symbol("link")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.detectedContent(for: [.url]).urls.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        if let value = context.selection.detectedContent(for: [.url]).urls.first, let url = URL(string: value) {
            let sourceBundleID = context.selection.sourceApp.bundleIdentifier
            if BrowserDetector.isBrowser(bundleIdentifier: sourceBundleID), let sourceBundleID {
                return .openURLInApp(url: url, appBundleIdentifier: sourceBundleID)
            }
            return .openURL(url)
        }
        return .failure(NSError(
            domain: Constants.actionErrorDomain,
            code: Constants.actionErrorCode,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "No valid URL found in selection.")]
        ))
    }
    
    public func extractURL(from text: String) -> URL? {
        Self.extractFirstURL(from: text)
    }

    public static func extractFirstURL(from text: String) -> URL? {
        NativeContentDetector.urls(in: text).first
    }
}
