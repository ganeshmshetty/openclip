// RichPasteboardPayload.swift
// OpenClip
//
// Pure Core value type representing multi-type clipboard content (plain text, RTF, HTML).
// Used by ActionResult.pasteContent and ActionResult.copyContent to support rich text formatting.
import Foundation

public struct RichPasteboardPayload: Sendable, Equatable {
    public var plainText: String?
    public var rtf: String?
    public var html: String?

    public init(plainText: String? = nil, rtf: String? = nil, html: String? = nil) {
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
    }
}
