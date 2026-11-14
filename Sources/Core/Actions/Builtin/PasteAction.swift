// PasteAction.swift
// OpenClip
//
// Implements the standard paste action that triggers clipboard paste simulation.
//
// Delivery: no `delivery` declared (default nil), so a secondary click derives `.copy` and shows
// the default "Copied" toast. Builtins and extensions therefore behave identically.
import Foundation

public struct PasteAction: ConfigurableAction {
    public let id = "builtin.paste"
    public var title: String { String(localized: "Paste") }
    public let preferenceIconName = "doc.on.clipboard"
    public var icon: ActionIcon { .text(String(localized: "Paste")) }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        // An OCR result is about recognized text, so pasting the unrelated clipboard is noise.
        guard context.selection.source != .ocr else { return false }
        // Unknown keeps Paste visible: a timed-out probe is not a disabled command.
        return ActionEligibility.isSatisfied(
            [.pasteDestination],
            selection: context.selection,
            capabilities: context.capabilities,
            unknownSatisfies: true
        )
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .simulatePaste
    }
}
