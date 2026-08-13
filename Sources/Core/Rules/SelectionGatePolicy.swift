// SelectionGatePolicy.swift
// OpenClip
//
// Gates whether OpenClip should attempt selection retrieval in a given app: skip UI roles
// that cannot hold text, only read when the cursor class suggests a text context, and require
// an existing selection before copying. Pure Core — no AppKit.
import Foundation

public struct SelectionGatePolicy: Codable, Sendable, Equatable {
    public let skipRoles: Set<String>
    public let allowedCursors: Set<CursorClass>
    public let requireSelectionBeforeCopy: Bool

    public init(
        skipRoles: Set<String> = [],
        allowedCursors: Set<CursorClass> = [.beam, .arrow, .pointingHand, .unknown],
        requireSelectionBeforeCopy: Bool = true
    ) {
        self.skipRoles = skipRoles
        self.allowedCursors = allowedCursors
        self.requireSelectionBeforeCopy = requireSelectionBeforeCopy
    }

    public static let `default` = SelectionGatePolicy(
        skipRoles: [
            "AXButton", "AXCheckBox", "AXColorWell", "AXDateField", "AXDisclosureTriangle",
            "AXMenu", "AXMenuBar", "AXMenuBarItem", "AXMenuButton", "AXMenuItem",
            "AXPopUpButton", "AXRadioButton", "AXScrollBar", "AXSlider", "AXTimeField",
            "AXToolbar", "AXValueIndicator"
        ],
        allowedCursors: [.beam, .arrow, .pointingHand, .unknown],
        requireSelectionBeforeCopy: true
    )

    public static let lenient = SelectionGatePolicy(
        skipRoles: [],
        allowedCursors: [.beam, .arrow, .pointingHand, .unknown],
        requireSelectionBeforeCopy: false
    )
}

public enum CursorClass: String, Codable, Sendable, CaseIterable {
    case beam
    case arrow
    case pointingHand
    case other
    case unknown
}