// AddCustomActionSheet.swift
// OpenClip
//
// Renders the modal sheet interface for creating new custom actions (Open URL, Text Snippet, Shell Script).
// Newly created actions are saved as first-class CustomAction models in SettingsStore and registered
// via ActionCoordinator, visually matching EditActionSheet.
import SwiftUI
import Core

@MainActor
public struct AddCustomActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Appearance State (matching EditActionSheet's Hero Header Card)
    @State private var customTitle: String = ""
    /// Expanded state of the inline icon chooser.
    @State private var showingIconPicker = false
    @State private var iconSymbol: String = "wand.and.stars"
    private let initialIconSymbol: String = "wand.and.stars"
    @State private var displayMode: Int = 0 // 0 = Show Icon, 1 = Show Text

    // Execution Logic State
    private enum ActionKind: Hashable {
        case openURL
        case textSnippet
        case shellScript
    }
    @State private var actionKind: ActionKind = .openURL
    @State private var customURLTemplate: String = "https://google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "**{text}**"
    @State private var customShellScript: String = "echo \"$OPENCLIP_TEXT\" | tr '[:lower:]' '[:upper:]'"
    @State private var replaceSelection: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Custom Action")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Content Area
            VStack(alignment: .leading, spacing: 12) {
                // Hero Header Card (Icon, Name & Display Mode)
                InsetGroupCard {
                    ActionAppearanceFields(
                        title: $customTitle,
                        displayTextFallback: "Custom Action",
                        iconSymbol: $iconSymbol,
                        initialIconSymbol: initialIconSymbol,
                        baseIcon: nil,
                        displayMode: $displayMode,
                        onPickIcon: {
                            withAnimation(.easeInOut(duration: 0.18)) { showingIconPicker.toggle() }
                        }
                    )

                    // This sheet is a creation flow, not a place you navigate into, so the chooser
                    // expands in the card instead of pushing a page.
                    if showingIconPicker {
                        Divider()
                        IconPickerView(selectedSymbol: $iconSymbol) {
                            withAnimation(.easeInOut(duration: 0.18)) { showingIconPicker = false }
                        }
                        .frame(height: 260)
                        .padding(14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Execution Logic Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXECUTION LOGIC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    InsetGroupCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Type")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Picker("", selection: $actionKind) {
                                    Text("Open URL").tag(ActionKind.openURL)
                                    Text("Text Snippet").tag(ActionKind.textSnippet)
                                    Text("Shell Script").tag(ActionKind.shellScript)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider()
                                .padding(.horizontal, 12)

                            Group {
                                switch actionKind {
                                case .openURL:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("URL Template")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextField("https://example.com/search?q={text}", text: $customURLTemplate)
                                            .textFieldStyle(.roundedBorder)
                                        Text("Use **{text}** or **{selection}** as a placeholder for the selected text.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                case .textSnippet:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Snippet Template")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextEditor(text: $customSnippetTemplate)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 70)
                                            .scrollContentBackground(.hidden)
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.primary.opacity(0.04))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Color.primary.opacity(0.12))
                                                    )
                                            )
                                        Text("Use **{text}** or **{selection}** as a placeholder for the selected text.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                case .shellScript:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Shell Script (Zsh)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        TextEditor(text: $customShellScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 90)
                                            .scrollContentBackground(.hidden)
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color.primary.opacity(0.04))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .stroke(Color.primary.opacity(0.12))
                                                    )
                                            )
                                        Toggle("Replace selected text with output", isOn: $replaceSelection)
                                            .font(.subheadline)
                                        Text("Use **$OPENCLIP_TEXT** for the selected text.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(16)

            // Footer
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Action") { addAction() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
    }

    private func addAction() {
        let trimmedTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let actionType: CustomActionType
        switch actionKind {
        case .openURL:
            actionType = .openURL(urlTemplate: customURLTemplate)
        case .textSnippet:
            actionType = .textSnippet(template: customSnippetTemplate)
        case .shellScript:
            actionType = .shellScript(script: customShellScript, replaceSelection: replaceSelection)
        }

        let id = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        let resolvedIcon = iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "wand.and.stars" : iconSymbol
        let newAction = CustomAction(
            id: id,
            title: trimmedTitle,
            iconName: resolvedIcon,
            type: actionType
        )

        ActionCoordinator.shared.saveCustomAction(newAction)

        if displayMode == 1 {
            ActionCustomizationManager.shared.setOverride(
                for: id,
                title: nil,
                symbol: nil,
                text: trimmedTitle
            )
        }

        dismiss()
    }
}
