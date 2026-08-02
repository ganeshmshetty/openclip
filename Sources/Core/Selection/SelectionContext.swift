// SelectionContext.swift
// OpenClip
//
// Represents the full context of a text selection event, including selected text, source application, screen coordinates, and app policy.
import Foundation
import CoreGraphics

public struct SelectionContext: Sendable {
    public let text: String
    public let sourceApp: any AppIdentifying
    public let cursorPosition: CGPoint
    public let mouseDownLocation: CGPoint?
    public let selectionBounds: CGRect?
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    
    public init(
        text: String,
        sourceApp: any AppIdentifying,
        cursorPosition: CGPoint,
        mouseDownLocation: CGPoint? = nil,
        selectionBounds: CGRect? = nil,
        timestamp: Date,
        appPolicy: AppPolicyContext
    ) {
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.mouseDownLocation = mouseDownLocation
        self.selectionBounds = selectionBounds
        self.timestamp = timestamp
        self.appPolicy = appPolicy
    }
}
