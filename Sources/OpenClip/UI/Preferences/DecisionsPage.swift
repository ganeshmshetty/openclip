// DecisionsPage.swift
// OpenClip
//
// Preferences → Decisions: providers, tool library, Live assist (peer to AIPage).
import SwiftUI
import Core

@MainActor
struct DecisionsPage: View {
    @ObservedObject private var manager = DecisionServiceManager.shared
    @ObservedObject private var live = DecisionLiveAssistEngine.shared
    @State private var providerStatus: String = ""

    var body: some View {
        Form {
            Section {
                EmptyView()
            } header: {
                SettingsHeroHeader(
                    glyph: .symbol(SettingsPage.decisions.systemImage, tint: SettingsPage.decisions.tint),
                    title: String(localized: "Decision Tools"),
                    subtitle: String(localized: "Judge selections with typed answers — yes/no, choices, scores — not rewritten essays.")
                )
            }

            DecisionConfigureForm()

            DecisionActionsSection()

            Section {
                Toggle(String(localized: "Enable Live assist"), isOn: Binding(
                    get: { manager.liveAssistEnabled },
                    set: { manager.liveAssistEnabled = $0 }
                ))
                if manager.liveAssistRemainingSeconds > 0 {
                    let minutes = max(1, Int((manager.liveAssistRemainingSeconds / 60).rounded(.up)))
                    Text(String(localized: "On from the menu bar for \(minutes) more min."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper(
                    String(localized: "Debounce: \(manager.liveAssistDebounceMS) ms"),
                    value: Binding(
                        get: { manager.liveAssistDebounceMS },
                        set: { manager.liveAssistDebounceMS = $0 }
                    ),
                    in: 100...300,
                    step: 50
                )
                LabeledContent(String(localized: "AX focus monitoring")) {
                    Text(live.axFocusMonitoringAvailable
                         ? String(localized: "Available")
                         : String(localized: "Not enabled yet"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Live assist")
            } footer: {
                Text(DecisionLiveAssistEngine.privacyBlurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!manager.isDecisionsEnabled)
        }
        .formStyle(.grouped)
        .task {
            let status = await manager.providerStatus()
            switch status {
            case .available:
                providerStatus = String(localized: "Provider available")
            case .unavailable(let reason):
                providerStatus = reason
            }
        }
    }
}

@MainActor
struct DecisionConfigureForm: View {
    @ObservedObject private var manager = DecisionServiceManager.shared

    var body: some View {
        Section {
            Picker(String(localized: "Provider"), selection: Binding(
                get: { manager.activeProviderType },
                set: { manager.activeProviderType = $0 }
            )) {
                ForEach(DecisionProviderType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }

            switch manager.activeProviderType {
            case .jev:
                TextField(String(localized: "Base URL"), text: Binding(
                    get: { manager.jevBaseURL },
                    set: { manager.jevBaseURL = $0 }
                ))
                SecureField(String(localized: "Jev API key"), text: $manager.jevAPIKey)
            case .laya:
                LayaRuntimeSection(model: Binding(
                    get: { manager.layaModel },
                    set: { manager.layaModel = $0 }
                ))
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("Keys are stored in SecretStore (~/.openclip/secrets.json); Laya runs locally with no key. Decision tools never paste generated essays.")
                .font(.caption)
        }
        .disabled(!manager.isDecisionsEnabled)
    }
}

@MainActor
struct DecisionActionsSection: View {
    @ObservedObject private var manager = DecisionServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        Section {
            ReorderableRows(
                ids: manager.tools.map(\.id),
                dragPreviewTitle: { id in manager.tools.first(where: { $0.id == id })?.title ?? id },
                onMove: { id, gap in manager.moveTool(id: id, toGap: gap) }
            ) { id in
                if let tool = manager.tools.first(where: { $0.id == id }) {
                    row(tool)
                }
            }

            SettingsDisclosureRow {
                router.push(.decisionNewTool)
            } content: {
                Label("Add Decision Tool", systemImage: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Text("Decision Tools")
                Spacer()
                Button("Reset Defaults") { manager.resetToolsToDefault() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
        } footer: {
            Text("These appear inside the Decision Tools group in the popup bar. Drag to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!manager.isDecisionsEnabled)
    }

    @ViewBuilder
    private func row(_ tool: DecisionToolPreset) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { tool.isEnabled },
                set: { newValue in
                    var updated = tool
                    updated.isEnabled = newValue
                    manager.updateTool(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button {
                router.push(.decisionTool(id: tool.id))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.title)
                        Text(tool.questions.first?.kind.rawValue ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
struct DecisionToolPage: View {
    let toolID: String
    @ObservedObject private var manager = DecisionServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var kind: DecisionQuestionKind = .noul
    @State private var loaded = false
    @State private var confirmingDelete = false

    private var tool: DecisionToolPreset? {
        manager.tools.first { $0.id == toolID }
    }

    private var isCustom: Bool {
        !DecisionDefaultPresets.all.contains { $0.id == toolID }
    }

    var body: some View {
        if tool != nil || loaded {
            SettingsEditorPage {
                Form {
                    TextField(String(localized: "Title"), text: $title)
                    DecisionAnswerTypePicker(kind: $kind)
                    TextField(String(localized: "Question prompt"), text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                }
            } footer: {
                HStack {
                    if isCustom {
                        if confirmingDelete {
                            Button("Cancel") { confirmingDelete = false }
                            Button("Delete", role: .destructive) {
                                manager.deleteTool(id: toolID)
                                router.pop()
                            }
                        } else {
                            Button("Delete Tool…", role: .destructive) { confirmingDelete = true }
                        }
                    }
                    Button("Duplicate") {
                        _ = manager.duplicateTool(id: toolID)
                    }
                    Spacer()
                    Button("Cancel") { router.pop() }
                    Button("Save") {
                        guard var updated = tool else { return }
                        updated.title = title.trimmingCharacters(in: .whitespaces)
                        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        if var q = updated.questions.first {
                            q.prompt = trimmedPrompt
                            updated.questions[0] = q.retyped(as: kind)
                        } else {
                            updated.questions = [DecisionQuestion(id: "primary", kind: .noul, prompt: trimmedPrompt).retyped(as: kind)]
                        }
                        manager.updateTool(updated)
                        router.pop()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded, let tool else { return }
                title = tool.title
                prompt = tool.questions.first?.prompt ?? ""
                kind = tool.questions.first?.kind ?? .noul
                loaded = true
            }
        } else {
            Color.clear.onAppear { router.pop() }
        }
    }
}

@MainActor
struct DecisionNewToolPage: View {
    @ObservedObject private var manager = DecisionServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    @State private var title = ""
    @State private var prompt = ""
    @State private var kind: DecisionQuestionKind = .noul

    var body: some View {
        SettingsEditorPage {
            Form {
                TextField(String(localized: "Title"), text: $title)
                DecisionAnswerTypePicker(kind: $kind)
                TextField(String(localized: "Question prompt"), text: $prompt, axis: .vertical)
                    .lineLimit(3...8)
            }
        } footer: {
            HStack {
                Spacer()
                Button("Cancel") { router.pop() }
                Button("Add") {
                    let question = DecisionQuestion(id: "primary", kind: .noul, prompt: prompt).retyped(as: kind)
                    let tool = DecisionServiceManager.makeCustomTool(title: title, questions: [question])
                    manager.updateTool(tool)
                    router.pop()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// The answer-type picker shared by the New Decision Tool and edit pages.
struct DecisionAnswerTypePicker: View {
    @Binding var kind: DecisionQuestionKind

    var body: some View {
        Picker(String(localized: "Answer type"), selection: $kind) {
            Text("Yes / No").tag(DecisionQuestionKind.noul)
            Text("Choice").tag(DecisionQuestionKind.choice)
            Text("Score").tag(DecisionQuestionKind.score)
        }
    }
}
