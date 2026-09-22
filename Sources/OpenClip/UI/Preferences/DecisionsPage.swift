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
                    subtitle: String(localized: "Judge selections with typed answers — yes/no or a choice — not rewritten essays.")
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
                LabeledContent(String(localized: "Accessibility")) {
                    if live.axFocusMonitoringAvailable {
                        Text("Granted").foregroundStyle(.secondary)
                    } else {
                        Button(String(localized: "Grant…")) {
                            PermissionManager.shared.requestAccessibilityPermission()
                        }
                    }
                }
                LabeledContent(String(localized: "Tools in Quick Assist")) {
                    Text(quickAssistSummary).foregroundStyle(.secondary)
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
        .onChange(of: manager.isLiveAssistActive) { _, _ in
            QuickAssistController.shared.syncWithSettings()
        }
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

extension DecisionsPage {
    /// "Safe to share?, Triage" — the tools that answer as you type, for the Live assist section.
    var quickAssistSummary: String {
        let titles = live.quickAssistTools.map(\.title)
        return titles.isEmpty ? String(localized: "None") : titles.joined(separator: ", ")
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
                        HStack(spacing: 4) {
                            Text(tool.questions.first?.kind.rawValue ?? "")
                            if tool.showsInQuickAssist {
                                Text("· Quick Assist")
                            }
                        }
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
    @State private var choicesText: String = ""
    @State private var showsInQuickAssist = false
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
                    if kind == .choice {
                        DecisionChoicesField(text: $choicesText)
                    }
                    TextField(String(localized: "Question prompt"), text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                    DecisionQuickAssistToggle(isOn: $showsInQuickAssist, tool: tool)
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
                        var q = updated.questions.first ?? DecisionQuestion(id: "primary", kind: .noul, prompt: trimmedPrompt)
                        q.prompt = trimmedPrompt
                        q = q.retyped(as: kind)
                        if kind == .choice {
                            q.options = DecisionQuestion.parseChoiceOptions(choicesText)
                        }
                        updated.questions = [q] + updated.questions.dropFirst()
                        updated.showsInQuickAssist = showsInQuickAssist
                        manager.updateTool(updated)
                        router.pop()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || !DecisionChoicesField.isValid(kind: kind, text: choicesText))
                }
            }
            .onAppear {
                guard !loaded, let tool else { return }
                title = tool.title
                prompt = tool.questions.first?.prompt ?? ""
                kind = tool.questions.first?.kind ?? .noul
                choicesText = (tool.questions.first?.options ?? []).joined(separator: "\n")
                showsInQuickAssist = tool.showsInQuickAssist
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
    @State private var choicesText = ""
    @State private var showsInQuickAssist = false

    var body: some View {
        SettingsEditorPage {
            Form {
                TextField(String(localized: "Title"), text: $title)
                DecisionAnswerTypePicker(kind: $kind)
                if kind == .choice {
                    DecisionChoicesField(text: $choicesText)
                }
                TextField(String(localized: "Question prompt"), text: $prompt, axis: .vertical)
                    .lineLimit(3...8)
                DecisionQuickAssistToggle(isOn: $showsInQuickAssist, tool: nil)
            }
        } footer: {
            HStack {
                Spacer()
                Button("Cancel") { router.pop() }
                Button("Add") {
                    var question = DecisionQuestion(id: "primary", kind: .noul, prompt: prompt).retyped(as: kind)
                    if kind == .choice {
                        question.options = DecisionQuestion.parseChoiceOptions(choicesText)
                    }
                    var tool = DecisionServiceManager.makeCustomTool(title: title, questions: [question])
                    tool.showsInQuickAssist = showsInQuickAssist
                    manager.updateTool(tool)
                    router.pop()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty || !DecisionChoicesField.isValid(kind: kind, text: choicesText))
            }
        }
    }
}

/// "Show in Quick Assist" for a tool. A bulk tool cannot answer as you type — it is a
/// deliberate, many-request run — so the toggle is off and disabled for it.
struct DecisionQuickAssistToggle: View {
    @Binding var isOn: Bool
    let tool: DecisionToolPreset?

    private var isSupported: Bool {
        guard let tool else { return true }
        return tool.bulkMode == .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(String(localized: "Show in Quick Assist"), isOn: $isOn)
                .disabled(!isSupported)
            Text(isSupported
                 ? String(localized: "Answers continuously in the floating window while Live assist is on.")
                 : String(localized: "Bulk tools run only when you pick them."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The list of choices for a `.choice` tool, shared by the New Decision Tool and edit pages:
/// one per line or comma-separated, at least two.
struct DecisionChoicesField: View {
    @Binding var text: String

    static func isValid(kind: DecisionQuestionKind, text: String) -> Bool {
        kind != .choice || DecisionQuestion.parseChoiceOptions(text).count >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                String(localized: "Choices"),
                text: $text,
                prompt: Text(String(localized: "billing, engineering, sales")),
                axis: .vertical
            )
            .lineLimit(2...6)
            Text(String(localized: "One per line or comma-separated; at least two. The model picks one and the tool shows it."))
                .font(.caption)
                .foregroundStyle(Self.isValid(kind: .choice, text: text) ? Color.secondary : Color.orange)
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
        }
    }
}
