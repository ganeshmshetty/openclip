import Foundation
#if canImport(AppKit)
import AppKit
import CoreGraphics
#endif
import Core

public struct PasteAction: Action {
    public let id = "builtin.paste"
    public let title = "Paste"
    public let icon = ActionIcon.symbol("doc.on.clipboard")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        #if canImport(AppKit)
        let hasString = NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        return hasString
        #else
        return true
        #endif
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .simulatePaste
    }
}
