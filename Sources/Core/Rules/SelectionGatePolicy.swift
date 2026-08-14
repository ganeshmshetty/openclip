// SelectionGatePolicy.swift
// OpenClip
//
// Gates whether OpenClip should attempt selection retrieval in a given app: skip UI roles
// that cannot hold text and only read when the cursor class suggests a text context. Pure Core —
// no AppKit. Copy-based reads are no longer pre-gated here; the pasteboard capture engine decides
// whether a selection actually existed by observing the clipboard change.
import Foundation

public struct SelectionGatePolicy: Codable, Sendable, Equatable {
    public let skipRoles: Set<String>
    public let allowedCursors: Set<CursorClass>

    public init(
        skipRoles: Set<String> = [],
        allowedCursors: Set<CursorClass> = [.beam, .arrow, .pointingHand, .unknown]
    ) {
        self.skipRoles = skipRoles
        self.allowedCursors = allowedCursors
    }

    public static let `default` = SelectionGatePolicy(
        skipRoles: [
            "AXButton", "AXCheckBox", "AXColorWell", "AXDateField", "AXDisclosureTriangle",
            "AXMenu", "AXMenuBar", "AXMenuBarItem", "AXMenuButton", "AXMenuItem",
            "AXPopUpButton", "AXRadioButton", "AXScrollBar", "AXSlider", "AXTimeField",
            "AXToolbar", "AXValueIndicator"
        ],
        allowedCursors: [.beam, .arrow, .pointingHand, .unknown]
    )

    public static let lenient = SelectionGatePolicy(
        skipRoles: [],
        allowedCursors: [.beam, .arrow, .pointingHand, .unknown]
    )
}

public enum CursorClass: String, Codable, Sendable, CaseIterable {
    case beam
    case arrow
    case pointingHand
    case other
    case unknown
}