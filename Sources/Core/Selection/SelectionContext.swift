// SelectionContext.swift
// OpenClip
//
// Represents the full context of a text selection event, including selected text, source application, screen coordinates, and app policy.
import Foundation
import CoreGraphics

public enum SelectionSource: Sendable {
    case selection, clipboard, ocr
}

public struct SelectionContext: Sendable {
    /// Retrieval correlation ID, carried through presentation without retaining content in logs.
    public let traceID: UInt64?
    /// Generation of observed selection/focus gestures; nil for untracked contexts.
    public let selectionGeneration: UInt64?
    public let text: String
    public let sourceApp: AppIdentity
    public let cursorPosition: CGPoint
    public let mouseDownLocation: CGPoint?
    public let selectionBounds: CGRect?
    public let timestamp: Date
    public let appPolicy: AppPolicyContext
    /// True when the text came from the clipboard (shortcut triggered with no selection), not from a live selection.
    public let isClipboardFallback: Bool
    public let source: SelectionSource
    /// Whether the source selection was confirmed editable by the selection reader. Nil means the
    /// reader did not establish editability. Clipboard and OCR input are never editable selections.
    public let isEditable: Bool?
    /// Whether the current destination was confirmed to accept paste. This is destination
    /// evidence, independent of where `text` came from.
    public let pasteTargetAvailable: Bool?
    public let html: String?
    public let rtf: String?
    /// Raw pasteboard representations captured alongside the text, including app-private types.
    public let flavors: [RichPasteboardFlavor]
    private let contentDetection: ContentDetectionCache

    public func detectedContent(for types: [ContentType]) -> DetectedContent {
        contentDetection.detect(types)
    }

    public init(
        text: String,
        sourceApp: AppIdentity = AppIdentity(bundleIdentifier: "com.openclip.unknown", localizedName: "Unknown"),
        cursorPosition: CGPoint = .zero,
        mouseDownLocation: CGPoint? = nil,
        selectionBounds: CGRect? = nil,
        timestamp: Date = Date(),
        appPolicy: AppPolicyContext = .default,
        isClipboardFallback: Bool = false,
        html: String? = nil,
        rtf: String? = nil,
        flavors: [RichPasteboardFlavor] = [],
        contentDetection: ContentDetectionCache? = nil,
        selectionGeneration: UInt64? = nil,
        source: SelectionSource? = nil,
        isEditable: Bool? = nil,
        pasteTargetAvailable: Bool? = nil,
        traceID: UInt64? = nil
    ) {
        self.traceID = traceID
        self.selectionGeneration = selectionGeneration
        self.text = text
        self.sourceApp = sourceApp
        self.cursorPosition = cursorPosition
        self.mouseDownLocation = mouseDownLocation
        self.selectionBounds = selectionBounds
        self.timestamp = timestamp
        self.appPolicy = appPolicy
        self.source = source ?? (isClipboardFallback ? .clipboard : .selection)
        self.isClipboardFallback = self.source == .clipboard
        self.isEditable = self.source == .selection ? isEditable : false
        self.pasteTargetAvailable = pasteTargetAvailable
        self.html = html
        self.rtf = rtf
        self.flavors = flavors
        self.contentDetection = contentDetection ?? ContentDetectionCache(text: text)
    }

    public func with(cursorPosition: CGPoint) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: cursorPosition,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: selectionBounds,
            timestamp: timestamp,
            appPolicy: appPolicy,
            isClipboardFallback: isClipboardFallback,
            html: html,
            rtf: rtf,
            flavors: flavors,
            contentDetection: contentDetection,
            selectionGeneration: selectionGeneration,
            source: source,
            isEditable: isEditable,
            pasteTargetAvailable: pasteTargetAvailable,
            traceID: traceID
        )
    }

    public func with(isEditable: Bool? = nil, pasteTargetAvailable: Bool? = nil) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: cursorPosition,
            mouseDownLocation: mouseDownLocation,
            selectionBounds: selectionBounds,
            timestamp: timestamp,
            appPolicy: appPolicy,
            isClipboardFallback: isClipboardFallback,
            html: html,
            rtf: rtf,
            flavors: flavors,
            contentDetection: contentDetection,
            selectionGeneration: selectionGeneration,
            source: source,
            isEditable: self.isEditable ?? isEditable,
            pasteTargetAvailable: pasteTargetAvailable ?? self.pasteTargetAvailable,
            traceID: traceID
        )
    }
}
