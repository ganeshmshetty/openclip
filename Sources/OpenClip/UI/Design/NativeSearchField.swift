// NativeSearchField.swift
// OpenClip
//
// A real `NSSearchField` for the places that need a search box inline in the
// content rather than in the toolbar (the toolbar ones use `.searchable`).
// Wrapping AppKit's control keeps the magnifier, the recents menu, the cancel
// button, the focus ring and the vibrancy behaviour the system already ships.
import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var controlSize: NSControl.ControlSize = .regular
    /// Called when the user presses Return; searches that are too expensive to
    /// run per keystroke (the Iconify catalog) hang off this instead of `text`.
    var onSubmit: ((String) -> Void)?

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.controlSize = controlSize
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: controlSize))
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldDidSubmit(_:))
        field.sendsWholeSearchString = onSubmit != nil
        field.sendsSearchStringImmediately = onSubmit == nil
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func searchFieldDidSubmit(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit?(sender.stringValue)
        }
    }
}
