// MultilineTextEditor.swift
// OpenClip
//
// A small plain-text `NSTextView` wrapper for the two places that need more than SwiftUI's
// multiline `TextField` offers: the AI preset prompt editor (insert a variable at the caret, accept
// it dragged in at the drop point, show it highlighted) and the popup's additional-instruction
// prompt (⏎ is a newline, ⌘⏎ submits, ⎋ cancels). Everything else is stock AppKit text editing —
// undo, cut/copy/paste, drag-and-drop of text — so a variable stays ordinary, movable text.
import AppKit
import SwiftUI

/// Imperative handle a SwiftUI parent holds to edit the text view at its caret. The editor binds
/// itself on creation; calls before that (or after teardown) are no-ops.
@MainActor
final class MultilineTextEditorHandle {
    fileprivate weak var textView: NSTextView?

    /// Replaces the current selection (or inserts at the caret) with `text` as one undoable edit,
    /// leaves the caret after it, and focuses the editor.
    func insertAtCaret(_ text: String) {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        var range = textView.selectedRange()
        if range.location == NSNotFound || NSMaxRange(range) > length {
            range = NSRange(location: length, length: 0)
        }
        textView.window?.makeFirstResponder(textView)
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

struct MultilineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    /// Occurrences of this literal are tinted with the accent color (the prompt variable).
    var highlightedToken: String? = nil
    var handle: MultilineTextEditorHandle? = nil
    var textInset = NSSize(width: 4, height: 6)
    var accessibilityLabel: String? = nil
    /// ⌘⏎ while the editor is focused. Plain ⏎ always inserts a newline.
    var onCommandReturn: (() -> Void)? = nil
    /// ⎋ while the editor is focused. nil leaves Escape to AppKit's default handling.
    var onEscape: (() -> Void)? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        // Prompts are code-like: keep braces, quotes and dashes exactly as typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .labelColor
        textView.textContainerInset = textInset
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(accessibilityLabel)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.isUpdatingFromBinding = true
        textView.string = text
        context.coordinator.isUpdatingFromBinding = false
        // A first insert before the user clicks in lands at the end, not at the very start.
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        configure(textView, coordinator: context.coordinator)
        context.coordinator.applyHighlight(to: textView)
        handle?.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        configure(textView, coordinator: context.coordinator)
        handle?.textView = textView
        if textView.string != text, !textView.hasMarkedText() {
            // An outside change (the Additional Instruction toggle inserting or removing the
            // variable) goes through the text system so it stays one undoable edit.
            let length = (textView.string as NSString).length
            let fullRange = NSRange(location: 0, length: length)
            let selection = textView.selectedRange()
            context.coordinator.isUpdatingFromBinding = true
            if textView.shouldChangeText(in: fullRange, replacementString: text) {
                textView.replaceCharacters(in: fullRange, with: text)
                textView.didChangeText()
            } else {
                textView.string = text
            }
            context.coordinator.isUpdatingFromBinding = false
            let newLength = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, newLength), length: 0))
            context.coordinator.applyHighlight(to: textView)
        }
    }

    private func configure(_ textView: EditorTextView, coordinator: Coordinator) {
        textView.placeholderString = placeholder
        textView.font = font
        textView.onCommandReturn = onCommandReturn
        textView.onEscape = onEscape
        textView.onFocusChange = onFocusChange
        coordinator.highlightedToken = highlightedToken
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineTextEditor
        var highlightedToken: String?
        /// True while the binding itself is being written into the view, so that write is not
        /// echoed back into the binding during a SwiftUI update pass.
        var isUpdatingFromBinding = false

        init(parent: MultilineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            applyHighlight(to: textView)
            textView.needsDisplay = true
            guard !isUpdatingFromBinding, parent.text != textView.string else { return }
            parent.text = textView.string
        }

        /// New typing never inherits the variable's tint from the character before the caret.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            textView.typingAttributes = baseAttributes(for: textView)
            return true
        }

        private func baseAttributes(for textView: NSTextView) -> [NSAttributedString.Key: Any] {
            [.font: textView.font ?? parent.font, .foregroundColor: NSColor.labelColor]
        }

        func applyHighlight(to textView: NSTextView) {
            // Re-attributing while an input method composes would break the composition.
            guard let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let string = storage.string as NSString
            let fullRange = NSRange(location: 0, length: string.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            if let token = highlightedToken, !token.isEmpty {
                var searchRange = fullRange
                while searchRange.length > 0 {
                    let found = string.range(of: token, options: [], range: searchRange)
                    guard found.location != NSNotFound else { break }
                    storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: found)
                    storage.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.12), range: found)
                    let next = NSMaxRange(found)
                    searchRange = NSRange(location: next, length: fullRange.length - next)
                }
            }
            storage.endEditing()
            textView.typingAttributes = baseAttributes(for: textView)
        }
    }
}

/// The text view behind `MultilineTextEditor`: draws the placeholder while empty and routes ⌘⏎ / ⎋.
final class EditorTextView: NSTextView {
    var placeholderString = "" {
        didSet { if oldValue != placeholderString { needsDisplay = true } }
    }
    var onCommandReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    static func isCommandReturn(_ event: NSEvent) -> Bool {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return isReturn && modifiers.contains(.command)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let onCommandReturn, window?.firstResponder === self, Self.isCommandReturn(event) {
            onCommandReturn()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let onCommandReturn, Self.isCommandReturn(event) {
            onCommandReturn()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
        } else {
            super.cancelOperation(sender)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        let width = bounds.width - origin.x * 2
        (placeholderString as NSString).draw(
            in: NSRect(x: origin.x, y: origin.y, width: max(0, width), height: bounds.height - origin.y),
            withAttributes: attributes
        )
    }
}
