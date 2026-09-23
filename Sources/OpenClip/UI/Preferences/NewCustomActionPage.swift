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
    @State private var iconSymbol: String = "plus"
    private let initialIconSymbol: String = "plus"
    @State private var displayMode: Int = 0 // 0 = Show Icon, 1 = Show Text

    // Execution Logic State
    private enum ActionKind: Hashable {
        case openURL
        case textSnippet
        case shellScript
        case javaScript
    }
    @State private var actionKind: ActionKind
    /// True when the page was opened from one of the quick-create cards, which already picked the
    /// kind: the Type picker is hidden so the chosen kind is never shown back to the user.
    @State private var locksKind: Bool
    @State private var customURLTemplate: String = "https://google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "**{text}**"
    @State private var customShellScript: String = "echo \"$OPENCLIP_TEXT\" | tr '[:lower:]' '[:upper:]'"
    @State private var customJavaScript: String = "function action(text) {\n    return text.toUpperCase();\n}"
    @State private var customJSIsAsync: Bool = false
    @State private var replaceSelection: Bool = false

    public init(initialKind: String? = nil) {
        let kind: ActionKind = switch initialKind {
        case "snippet", "textSnippet": .textSnippet
        case "shell", "shellScript": .shellScript
        case "js", "javascript": .javaScript
        default: .openURL
        }
        _actionKind = State(initialValue: kind)
        _locksKind = State(initialValue: initialKind != nil)
        let icon: String = switch kind {
        case .openURL: "safari.fill"
        case .textSnippet: "text.quote"
        case .shellScript: "terminal.fill"
        case .javaScript: "curlybraces"
        }
        _iconSymbol = State(initialValue: icon)
        if kind == .javaScript {
            _replaceSelection = State(initialValue: true)
        }
    }

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
                        displayMode: $displayMode
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
                            if !locksKind {
                                HStack {
                                    Text("Type")
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Picker("", selection: $actionKind) {
                                        Text("Open URL").tag(ActionKind.openURL)
                                        Text("Text Snippet").tag(ActionKind.textSnippet)
                                        Text("Shell Script").tag(ActionKind.shellScript)
                                        Text("JavaScript").tag(ActionKind.javaScript)
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                Divider()
                                    .padding(.horizontal, 12)
                            }

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
                                case .javaScript:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("JavaScript (JSC)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextEditor(text: $customJavaScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 120)
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
                                        Toggle("Run asynchronously (enable promises & fetch)", isOn: $customJSIsAsync)
                                            .font(.subheadline)
                                        Text("Return a value from **action(text)**, or use **openclip.copy()**, **openclip.paste()**, **openclip.fetch()**, etc.")
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
        case .javaScript:
            actionType = .javaScript(script: customJavaScript, isAsync: customJSIsAsync, replaceSelection: replaceSelection)
        }

        let id = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        let resolvedIcon = iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "plus" : iconSymbol
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
