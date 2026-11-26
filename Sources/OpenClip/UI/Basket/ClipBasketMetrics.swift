// ClipBasketMetrics.swift
// OpenClip
//
// Presentation sizing for the Clip Basket pill and expanded stack. Kept in the App target so Core
// stays free of UI vocabulary.
import CoreGraphics

enum ClipBasketMetrics {
    static let collapsedWidth: CGFloat = 228
    static let expandedWidth: CGFloat = 272
    static let maxHeight: CGFloat = 360
    static let collapsedHeight: CGFloat = 40
    static let rowHeight: CGFloat = 40
    static let cornerRadius: CGFloat = 14
    static let rowCornerRadius: CGFloat = 8
    static let rowMaxTextLines = 2
    static let maxPreviewCharacters = 46
    static let dragThreshold: CGFloat = 3
}
