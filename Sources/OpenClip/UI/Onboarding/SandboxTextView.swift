// SandboxTextView.swift
// OpenClip
//
// NSViewRepresentable wrapping an NSTextView for the onboarding sandbox.
// Detects text selection, triggers live feedback callback, and posts
// SelectionContext so PopupWindowController presents the real popup bar.
import SwiftUI
import AppKit
import Core

@MainActor
struct SandboxTextView: NSViewRepresentable {
    let text: String
    var onSelection: (() -> Void)? = nil

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelection: (() -> Void)?

        init(onSelection: (() -> Void)?) {
            self.onSelection = onSelection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let string = textView.string as NSString? else { return }
            let selectedText = string.substring(with: range)
            onSelection?()

            // Calculate screen coordinates for the selection
            var selectionBounds: CGRect? = nil
            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let rectInWindow = textView.convert(rect, to: nil)
                if let window = textView.window {
                    let screenRect = window.convertToScreen(rectInWindow)
                    selectionBounds = screenRect
                }
            }

            let cursor = selectionBounds.map { CGPoint(x: $0.midX, y: $0.maxY) } ?? NSEvent.mouseLocation
            let appIdentity = AppIdentity(bundleIdentifier: Bundle.main.bundleIdentifier, localizedName: "OpenClip")
            let context = SelectionContext(
                text: selectedText,
                sourceApp: appIdentity,
                cursorPosition: cursor,
                mouseDownLocation: nil,
                selectionBounds: selectionBounds,
                timestamp: Date(),
                appPolicy: .default
            )

            NotificationCenter.default.post(name: Notification.Name("OpenClipShowSandboxPopup"), object: context)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSelection = onSelection
    }
}
