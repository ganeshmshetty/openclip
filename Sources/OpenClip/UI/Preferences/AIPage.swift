// AIPage.swift
// OpenClip
//
// The AI settings page: which engine answers, and the library of prompts that appear in the AI
// Tools group — with each prompt a page of its own. Whether AI Tools is on at all is the switch in
// the toolbar, beside the back and forward arrows, the same as an installed extension's.
//
// AI settings used to hang off the gear on the "AI Tools" row of the Actions list, which opened a
// fixed 440x480 popover with its own segmented sub-tabs and a sheet on top of those for editing a
// prompt. It is a whole provider's worth of configuration, not a per-action setting, so it gets the
// same treatment as an installed extension: a row in the sidebar and a page.

import SwiftUI
import Core

@MainActor
struct AIPage: View {
    @ObservedObject private var aiManager = AIServiceManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeroHeader(
                glyph: .symbol(SettingsPage.ai.systemImage, tint: SettingsPage.ai.tint),
                title: String(localized: "AI Tools"),
                subtitle: String(localized: "Rewrite, summarize, translate or ask about the selected text, using the engine below.")
            )

            Form {
                AIConfigureForm(embedded: true)

                AIActionsSection()
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - One prompt

/// Editing one AI prompt. This was a `.sheet` opened from inside the AI popover, so it dimmed the
/// popover, whatever else was still floating, and the window. As a page it is just the next level.
@MainActor
struct AIPresetPage: View {
    let presetID: String

    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var loaded = false
    @State private var isConfirmingDelete = false

    private var preset: AIActionPreset? {
        aiManager.presets.first(where: { $0.id == presetID })
    }

    private var isCustom: Bool {
        !AIServiceManager.defaultPresets.contains(where: { $0.id == presetID })
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        if preset != nil || loaded {
            SettingsEditorPage {
                AIPromptFields(title: $title, prompt: $prompt)
            } footer: {
                HStack(spacing: 12) {
                    if isCustom {
                        if isConfirmingDelete {
                            Button("Cancel") { isConfirmingDelete = false }
                            Button("Delete", role: .destructive) {
                                deletePreset()
                                router.pop()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button("Delete Action…", role: .destructive) {
                                isConfirmingDelete = true
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }

                    Spacer()

                    Button("Cancel") { router.pop() }
                        .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        guard var updated = preset else { return }
                        updated.title = title.trimmingCharacters(in: .whitespaces)
                        updated.prompt = prompt.trimmingCharacters(in: .whitespaces)
                        aiManager.updatePreset(updated)
                        router.pop()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear {
                guard !loaded, let preset else { return }
                title = preset.title
                prompt = preset.prompt
                loaded = true
            }
        } else {
            // The preset went away (Reset Defaults while this page was open); go back to the list.
            Color.clear.onAppear { router.pop() }
        }
    }

    private func deletePreset() {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == presetID })
        aiManager.presets = list
    }
}

/// Adding a prompt, as the next page rather than a sheet over everything.
@MainActor
struct AINewPresetPage: View {
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var title: String = ""
    @State private var prompt: String = ""

    private var canAdd: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !prompt.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        SettingsEditorPage {
            AIPromptFields(
                title: $title,
                prompt: $prompt,
                titlePlaceholder: String(localized: "e.g. Simplify"),
                promptPlaceholder: String(localized: "e.g. Rewrite text using simple 5th-grade vocabulary")
            )
        } footer: {
            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") { router.pop() }
                    .keyboardShortcut(.cancelAction)

                Button("Add Action") {
                    _ = aiManager.addCustomPreset(title: title, prompt: prompt)
                    router.pop()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The two fields a prompt has, in one card.
private struct AIPromptFields: View {
    @Binding var title: String
    @Binding var prompt: String
    var titlePlaceholder: String = String(localized: "Title")
    var promptPlaceholder: String = String(localized: "Prompt instruction...")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InsetGroupCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Action Title")
                            .font(.subheadline)
                        Spacer()
                        TextField(titlePlaceholder, text: $title)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt Instruction")
                            .font(.subheadline)
                        TextField(promptPlaceholder, text: $prompt, axis: .vertical)
                            .lineLimit(4...12)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            Text("The selected text is appended to the instruction when the action runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}
