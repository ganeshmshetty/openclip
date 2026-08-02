// AIActionsTab.swift
// OpenClip
//
// Renders the dedicated preferences tab for enabling, configuring, and adding custom AI actions for the popup bar.
import SwiftUI

@MainActor
public struct AIActionsTab: View {
    @ObservedObject private var aiManager = AIServiceManager.shared
    @State private var showingAddPresetSheet = false
    @State private var newTitle: String = ""
    @State private var newPrompt: String = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section(header: HStack {
                    Text("Configured AI Actions")
                    Spacer()
                    Button("Reset Defaults") {
                        aiManager.resetPresetsToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enable or disable AI actions, edit prompt instructions, or add custom actions for the popup bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(aiManager.presets) { preset in
                            HStack(alignment: .top, spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { preset.isEnabled },
                                    set: { newValue in
                                        var updated = preset
                                        updated.isEnabled = newValue
                                        aiManager.updatePreset(updated)
                                    }
                                ))
                                .labelsHidden()

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(preset.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Button(action: {
                                            deletePreset(preset)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete Action")
                                    }

                                    TextField("Prompt instruction...", text: Binding(
                                        get: { preset.prompt },
                                        set: { newPrompt in
                                            var updated = preset
                                            updated.prompt = newPrompt
                                            aiManager.updatePreset(updated)
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)

                            if preset.id != aiManager.presets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button(action: {
                    showingAddPresetSheet = true
                }) {
                    Label("Add Custom AI Action", systemImage: "plus.circle")
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(isPresented: $showingAddPresetSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Custom AI Action")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Action Title")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Simplify", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Instruction")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Rewrite text using simple 5th-grade vocabulary", text: $newPrompt)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    Button("Add Action") {
                        let id = "custom_\(UUID().uuidString.prefix(8))"
                        let preset = AIActionPreset(id: id, title: newTitle.trimmingCharacters(in: .whitespaces), prompt: newPrompt.trimmingCharacters(in: .whitespaces), isEnabled: true)
                        aiManager.updatePreset(preset)
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func deletePreset(_ preset: AIActionPreset) {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == preset.id })
        aiManager.presets = list
    }
}
