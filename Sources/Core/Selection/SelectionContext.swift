// SelectionContext.swift
// OpenClip
//
// Represents the full context of a text selection event, including selected text, source application, screen coordinates, and app policy.
import Foundation
import CoreGraphics

public struct SelectionContext: Sendable {
    public let text: String
    public let sourceApp: AppIdentity
    public let cursorPosition: CGPoint
    public let mouseDownLocation: CGPoint?
    public let selectionBounds: CGRect?
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    /// True when the text came from the clipboard (shortcut triggered with no selection), not from a live selection.
    public let isClipboardFallback: Bool
    public let html: String?
    public let rtf: String?
    
    public init(
        text: String,
        sourceApp: AppIdentity,
        cursorPosition: CGPoint,
        mouseDownLocation: CGPoint? = nil,
        selectionBounds: CGRect? = nil,
        timestamp: Date,
        appPolicy: AppPolicyContext,
        isClipboardFallback: Bool = false,
        html: String? = nil,
        rtf: String? = nil
    ) {
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.mouseDownLocation = mouseDownLocation
        self.selectionBounds = selectionBounds
        self.timestamp = timestamp
        self.appPolicy = appPolicy
        self.isClipboardFallback = isClipboardFallback
        self.html = html
        self.rtf = rtf
    }
}
