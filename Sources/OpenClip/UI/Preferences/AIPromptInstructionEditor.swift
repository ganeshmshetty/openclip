// AIPromptInstructionEditor.swift
// OpenClip
//
// The body of an AI action's "Prompt Instruction" card, shared by the AI action editor and the New
// AI Action page: the multiline prompt editor plus the "Additional Instruction" switch. Turning the
// switch on appends `{{additional_instruction}}` (unless the prompt already has it) and offers the
// variable as a chip that can be dragged into the prompt at the drop point or clicked to insert at
// the caret; turning it off removes the variable again. The variable is ordinary text afterwards —
// typed, cut, pasted or moved like anything else. The string rules live in `AIAdditionalInstruction`.
import SwiftUI
import AppKit

struct AIPromptInstructionEditor: View {
    @Binding var prompt: String
    @Binding var requestsAdditionalInstruction: Bool
    var placeholder: String
    /// Shows "Prompt cannot be empty." under an empty prompt (the editor of an existing action).
    var showsEmptyPromptError = false

    @State private var editorHandle = MultilineTextEditorHandle()
    @State private var isEditorFocused = false

    private var variable: String { AIAdditionalInstruction.placeholder }
    private var promptHasVariable: Bool { AIAdditionalInstruction.containsPlaceholder(prompt) }

    /// The switch edits the prompt too: on inserts the variable, off removes it.
    private var additionalInstructionBinding: Binding<Bool> {
        Binding(
            get: { requestsAdditionalInstruction },
            set: { isOn in
                guard isOn != requestsAdditionalInstruction else { return }
                prompt = isOn
                    ? AIAdditionalInstruction.insertingPlaceholder(into: prompt)
                    : AIAdditionalInstruction.removingPlaceholder(from: prompt)
                requestsAdditionalInstruction = isOn
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                editor

                if showsEmptyPromptError && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Prompt cannot be empty.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("The selected text is appended to the instruction when the action runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
            .padding(.vertical, SettingsDesignTokens.sectionCardPaddingV)

            SettingsDivider()

            SettingsRow(
                title: "Additional Instruction",
                subtitle: "Ask for a one-time instruction each time this action runs.",
                systemImage: "text.badge.plus",
                plainIcon: true,
                descriptionOnHover: true
            ) {
                Toggle("", isOn: additionalInstructionBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(String(localized: "Additional Instruction"))
            }

            if requestsAdditionalInstruction {
                variableControls
                    .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                    .padding(.bottom, SettingsDesignTokens.sectionCardPaddingV)
            } else if promptHasVariable {
                Text("Turn on Additional Instruction to use {{additional_instruction}}. Until then it is left out when the action runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                    .padding(.bottom, SettingsDesignTokens.sectionCardPaddingV)
            }
        }
    }

    private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return MultilineTextEditor(
            text: $prompt,
            placeholder: placeholder,
            font: .systemFont(ofSize: NSFont.systemFontSize),
            highlightedToken: requestsAdditionalInstruction ? variable : nil,
            handle: editorHandle,
            accessibilityLabel: String(localized: "Prompt Instruction"),
            onFocusChange: { focused in isEditorFocused = focused }
        )
        .frame(height: 150)
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                isEditorFocused ? Color.accentColor.opacity(0.7) : Color(nsColor: .separatorColor),
                lineWidth: isEditorFocused ? 2 : 1
            )
        )
    }

    private var variableControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                variableChip

                Button("Insert at Cursor") {
                    editorHandle.insertAtCaret(variable)
                }
                .controlSize(.small)

                Spacer(minLength: 0)
            }

            Text("Drag the variable into the prompt or insert it at the cursor. When the action runs, the instruction you enter replaces it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !promptHasVariable {
                Label("The prompt has no {{additional_instruction}}. The instruction will be added at the end.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The variable as a token: drag it to a position in the prompt, or click it to insert at the
    /// caret. Dropping hands the editor plain text, so it lands wherever the drop caret is.
    private var variableChip: some View {
        Text(verbatim: variable)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
            .contentShape(Capsule())
            .onTapGesture { editorHandle.insertAtCaret(variable) }
            .onDrag { NSItemProvider(object: variable as NSString) }
            .help(String(localized: "Drag into the prompt, or click to insert at the cursor"))
            .accessibilityLabel(String(localized: "Additional instruction variable"))
            .accessibilityAddTraits(.isButton)
    }
}
