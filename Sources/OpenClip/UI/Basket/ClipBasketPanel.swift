// ClipBasketPanel.swift
// OpenClip
//
// Non-activating floating panel for the Clip Basket. Like the popup, it never becomes key or main;
// the transparent shadow ring is excluded from hit-testing.
import AppKit
import SwiftUI
import Core

@MainActor
final class ClipBasketPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    final class ContentView: NSHostingView<AnyView> {
        static func isInsideClickableRegion(point: NSPoint, bounds: NSRect) -> Bool {
            bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset).contains(point)
        }

        override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
            guard Thread.isMainThread else { return false }
            return MainActor.assumeIsolated {
                Self.isInsideClickableRegion(point: point, bounds: bounds)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated {
                guard Self.isInsideClickableRegion(point: point, bounds: bounds) else { return nil }
                return super.hitTest(point)
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            let clickable = bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)
            if !clickable.isEmpty {
                addCursorRect(clickable, cursor: .arrow)
            }
        }
    }
}
