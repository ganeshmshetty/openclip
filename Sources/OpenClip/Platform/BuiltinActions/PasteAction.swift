import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif
import Core

public struct PasteAction: Action {
    public let id = "builtin.paste"
    public let title = "Paste"
    public var icon: ActionIcon {
        if UserDefaults.standard.bool(forKey: "action.paste.useText") {
            return .text("Paste")
        }
        return .symbol("clipboard")
    }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        if context.selection.appPolicy.assumePaste { return true }
        #if canImport(AppKit)
        return (NSPasteboard.general.pasteboardItems?.count ?? 0) > 0
        #else
        return true
        #endif
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .simulatePaste
    }
}
