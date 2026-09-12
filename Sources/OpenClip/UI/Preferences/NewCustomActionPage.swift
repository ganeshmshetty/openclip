// NewCustomActionPage.swift
// OpenClip
//
// Creating a custom action (Open URL, Text Snippet, Shell Script) as a page of the Settings
// window. Newly created actions are saved as first-class CustomAction models in SettingsStore and
// registered via ActionCoordinator; the page mirrors the action editor so the two feel like one.
import SwiftUI
import Core

@MainActor
public struct NewCustomActionPage: View {
    @ObservedObject private var router = SettingsRouter.shared

    // Appearance State (matching ActionEditorPage's Hero Header Card)
    @State private var customTitle: String = ""
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
        SettingsEditorPage {
            VStack(alignment: .leading, spacing: 14) {
                // Hero Header Card (Icon, Name & Display Mode)
                InsetGroupCard {
                    ActionAppearanceFields(
                        title: $customTitle,
                        displayTextFallback: String(localized: "Custom Action"),
                        iconSymbol: $iconSymbol,
                        initialIconSymbol: initialIconSymbol,
                        baseIcon: nil,
                        displayMode: $displayMode,
                        onPickIcon: {
                            router.pushIconPicker(writingTo: $iconSymbol)
                        }
                    )
                }

                // Execution Logic Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXECUTION LOGIC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    InsetGroupCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Type")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
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
                                            .foregroundStyle(.secondary)
                                        TextField("https://example.com/search?q={text}", text: $customURLTemplate)
                                            .textFieldStyle(.roundedBorder)
                                        Text("Use **{text}** or **{selection}** as a placeholder for the selected text.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                case .textSnippet:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Snippet Template")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextEditor(text: $customSnippetTemplate)
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
                                        Text("Use **{text}** or **{selection}** as a placeholder for the selected text.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                case .shellScript:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Shell Script (Zsh)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextEditor(text: $customShellScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 110)
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
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        } footer: {
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { router.pop() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Action") { addAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
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

        router.pop()
    }
}
