// AITab.swift
// OpenClip
//
// Renders the AI preferences view with top-bar sub-tab switching between AI Engine Configuration and AI Actions Management.
import SwiftUI

public enum AISubTab: String, CaseIterable, Identifiable, Sendable {
    case configure = "Configure"
    case actions = "Actions"
    public var id: String { rawValue }
}

@MainActor
public struct AITab: View {
    @Binding var selectedSubTab: AISubTab
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var editingPreset: AIActionPreset? = nil
    @State private var showingAddPresetSheet = false
    @State private var newTitle: String = ""
    @State private var newPrompt: String = ""
    
    public init(selectedSubTab: Binding<AISubTab> = .constant(.configure)) {
        self._selectedSubTab = selectedSubTab
    }
    
    public var body: some View {
        Group {
            switch selectedSubTab {
            case .configure:
                AIConfigureForm()
            case .actions:
                actionsView
            }
        }
    }

    // MARK: - Actions View
    private var actionsView: some View {
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
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(aiManager.presets) { preset in
                            HStack(alignment: .center, spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { preset.isEnabled },
                                    set: { newValue in
                                        var updated = preset
                                        updated.isEnabled = newValue
                                        aiManager.updatePreset(updated)
                                    }
                                ))
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "Enable \(preset.title)"))

                                Text(preset.title)
                                    .font(.system(size: 13, weight: .medium))

                                Spacer()

                                Button(action: {
                                    editingPreset = preset
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit Action Prompt")
                                .accessibilityLabel("Edit Action Prompt")

                                if isCustomPreset(preset) {
                                    Button(action: {
                                        deletePreset(preset)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete Custom Action")
                                    .accessibilityLabel("Delete Custom Action")
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
        .sheet(item: $editingPreset) { preset in
            EditAIPresetSheet(
                preset: preset,
                isCustom: isCustomPreset(preset),
                onSave: { updated in
                    aiManager.updatePreset(updated)
                },
                onDelete: {
                    deletePreset(preset)
                }
            )
        }
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

    private func isCustomPreset(_ preset: AIActionPreset) -> Bool {
        !AIServiceManager.defaultPresets.contains(where: { $0.id == preset.id })
    }

    private func deletePreset(_ preset: AIActionPreset) {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == preset.id })
        aiManager.presets = list
    }
}

struct EditAIPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preset: AIActionPreset
    let isCustom: Bool
    let onSave: (AIActionPreset) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var prompt: String

    init(preset: AIActionPreset, isCustom: Bool, onSave: @escaping (AIActionPreset) -> Void, onDelete: @escaping () -> Void) {
        self.preset = preset
        self.isCustom = isCustom
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: preset.title)
        _prompt = State(initialValue: preset.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit AI Action")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Action Title")
                    .font(.caption)
                    .fontWeight(.medium)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt Instruction")
                    .font(.caption)
                    .fontWeight(.medium)
                TextField("Prompt instruction...", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                if isCustom {
                    Button("Delete Action", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    var updated = preset
                    updated.title = title.trimmingCharacters(in: .whitespaces)
                    updated.prompt = prompt.trimmingCharacters(in: .whitespaces)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Modal configuration sheet for AI Tools, opened from the gear icon in the Actions tab.
@MainActor
public struct ConfigureAISheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubTab: AISubTab

    public init(initialSubTab: AISubTab = .configure) {
        _selectedSubTab = State(initialValue: initialSubTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text(String(localized: "AI Tools"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Picker("", selection: $selectedSubTab) {
                    Text(String(localized: "Configure")).tag(AISubTab.configure)
                    Text(String(localized: "Actions")).tag(AISubTab.actions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            AITab(selectedSubTab: $selectedSubTab)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .frame(width: 440, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

