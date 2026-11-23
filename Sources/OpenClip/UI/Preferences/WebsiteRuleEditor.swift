// WebsiteRuleEditor.swift
// OpenClip
//
// Adds the page patterns that silence the automatic popup.
import SwiftUI
import Core

@MainActor
struct WebsiteRuleEditor: View {
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Website")
                .font(.headline)
            Text("The popup stays off on these sites. The keyboard shortcut still works.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .frame(minHeight: 150)

            Text("One pattern per line, for example google.com/maps*. Use * as a wildcard.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(patterns.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var patterns: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func add() {
        onAdd(patterns)
        dismiss()
    }
}
