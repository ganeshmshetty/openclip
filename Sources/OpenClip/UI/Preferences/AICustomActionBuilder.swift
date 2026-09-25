// AICustomActionBuilder.swift
// OpenClip
//
// Single-file builder for creating custom actions from natural language using AI.
// Produces self-contained openclip.json extension manifests directly, with zero-effort
// AI behavior inference, clean abstraction, a mini code peek, and swift spring animations.

import SwiftUI
import AppKit
import JavaScriptCore
import Core

// MARK: - Inferred Delivery Mode

public enum AIActionDeliveryMode: String, CaseIterable, Identifiable, Sendable, Hashable, Equatable {
    case replace = "replace"
    case copy = "copy"
    case preview = "preview"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .replace: return String(localized: "Paste")
        case .copy: return String(localized: "Copy")
        case .preview: return String(localized: "Show")
        }
    }

    public var icon: String {
        switch self {
        case .replace: return "arrow.triangle.2.circlepath"
        case .copy: return "doc.on.doc"
        case .preview: return "eye"
        }
    }
}

// MARK: - Synthesis Model

public struct AICustomActionSynthesis: Sendable, Equatable {
    public var title: String
    public var description: String
    public var iconSymbol: String
    public var kind: String // "javascript", "shell", "url", "textsnippet"
    public var scriptCode: String
    public var urlTemplate: String?
    public var delivery: AIActionDeliveryMode
    public var isAsync: Bool

    public init(
        title: String,
        description: String,
        iconSymbol: String,
        kind: String,
        scriptCode: String,
        urlTemplate: String? = nil,
        delivery: AIActionDeliveryMode,
        isAsync: Bool = false
    ) {
        self.title = title
        self.description = description
        self.iconSymbol = iconSymbol
        self.kind = kind
        self.scriptCode = scriptCode
        self.urlTemplate = urlTemplate
        self.delivery = delivery
        self.isAsync = isAsync
    }
}

// MARK: - Manifest Decoding Payload

private struct AIManifestResponse: Codable {
    let identifier: String?
    let name: String?
    let description: String?
    let action: ActionDetail?
    let actions: [ActionDetail]?

    struct ActionDetail: Codable {
        let title: String?
        let icon: String?
        let type: String?
        let scriptCode: String?
        let url: String?
        let output: String?
        let result: String?
        let isAsync: Bool?
    }

    var resolvedAction: ActionDetail? {
        action ?? actions?.first
    }
}

// MARK: - AI Generation Service

@MainActor
public enum AICustomActionService {

    private static let systemPromptText: String = """
    You are an expert OpenClip macOS extension architect.
    Your job is to generate a valid, self-contained OpenClip extension manifest according to the user's request.

    OUTPUT FORMAT:
    Output your answer or response inside <result>...</result> tags.
    Inside <result>, output ONLY a valid JSON object matching the openclip.json schema below. Do not wrap in markdown fences or include explanations.

    SCHEMA:
    {
      "identifier": "com.openclip.user.<slug>",
      "name": "<Concise Action Name>",
      "description": "<Concise 1-sentence description of what this action does>",
      "action": {
        "title": "<Concise Title>",
        "icon": "<SF Symbol name, e.g. textformat, curlybraces, arrow.triangle.2.circlepath, doc.on.clipboard, terminal, wand.and.stars, link>",
        "type": "javascript",
        "scriptCode": "<JavaScript function action(text) { ... }>",
        "output": "text",
        "result": "<paste-or-copy | copy | preview>",
        "isAsync": false
      }
    }

    RULES:
    1. Default to "type": "javascript".
       - Entry point function MUST be: function action(text) { ... }
       - Return the transformed text as a string.
       - If calling web APIs, use openclip.fetch(url, options) and set "isAsync": true.
       - macOS JavaScriptCore environment: NO browser DOM (no window, document, atob, btoa). Implement algorithms (e.g. Base64, hashing, formatting) in pure JS.
       - For web searches or opening links, use "type": "url" with "url": "https://...{query}".
    2. Infer Delivery ("result"):
       - "paste-or-copy": When the action transforms selected text (e.g. format, convert, case change, translate).
       - "copy": When the action extracts or generates text to save to clipboard.
       - "preview": When the action calculates stats, counts, or informational preview without replacing.
    3. SF Symbol: Choose an existing, relevant SF Symbol name for macOS 14+.
    \(AIRequestSupport.standalonePromptMarker)
    """

    public static func generate(userPrompt: String) async throws -> AICustomActionSynthesis {
        let aiManager = AIServiceManager.shared
        guard aiManager.isAIEnabled else {
            throw AIError.providerUnavailable(String(localized: "AI features are disabled. Please enable AI in Preferences → AI."))
        }

        let provider = aiManager.currentProvider
        let fullInstruction = "\(systemPromptText)\n\nUser Request: \(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))"

        let rawResponse = try await provider.process(prompt: fullInstruction, text: "")
        let jsonString = cleanJSONResponse(rawResponse)

        guard let data = jsonString.data(using: .utf8) else {
            throw AIError.invalidResponse
        }

        let manifest: AIManifestResponse
        do {
            manifest = try JSONDecoder().decode(AIManifestResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }

        guard let action = manifest.resolvedAction else {
            throw AIError.invalidResponse
        }

        let rawType = (action.type ?? "javascript").lowercased()
        let kind: String
        switch rawType {
        case "url", "websearch", "web", "search":
            kind = "url"
        case "shell", "shellinline", "script":
            kind = "shell"
        case "textsnippet", "snippet", "text":
            kind = "textsnippet"
        default:
            kind = "javascript"
        }

        let scriptCode = action.scriptCode ?? ""
        let isAsync = action.isAsync ?? false

        // Pre-flight JavaScriptCore syntax validation for JavaScript actions
        if kind == "javascript" && !scriptCode.isEmpty {
            let context = JSContext()
            let checkScript = "function __openclip_syntax_check__() {\n\(scriptCode)\n}"
            _ = context?.evaluateScript(checkScript)
            if let exception = context?.exception, !exception.isUndefined {
                Log.ai.error("AI generated JavaScript with syntax issue: \(exception.toString() ?? "")")
            }
        }

        let delivery: AIActionDeliveryMode
        let resString = (action.result ?? "").lowercased()
        if resString == "copy" {
            delivery = .copy
        } else if resString == "preview" || resString == "open" {
            delivery = .preview
        } else {
            delivery = .replace
        }

        let title = action.title ?? manifest.name ?? "Custom Action"
        let description = manifest.description ?? ""
        let icon = sanitizeIcon(action.icon ?? "wand.and.stars")

        return AICustomActionSynthesis(
            title: title,
            description: description,
            iconSymbol: icon,
            kind: kind,
            scriptCode: scriptCode,
            urlTemplate: action.url,
            delivery: delivery,
            isAsync: isAsync
        )
    }

    private static func cleanJSONResponse(_ raw: String) -> String {
        var text = AIRequestSupport.extractResultText(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            if lines.count >= 2 {
                let stripped = lines.dropFirst().dropLast().joined(separator: "\n")
                text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func sanitizeIcon(_ icon: String) -> String {
        var clean = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("symbol(") && clean.hasSuffix(")") {
            clean = String(clean.dropFirst(7).dropLast(1))
        }
        return clean.isEmpty ? "wand.and.stars" : clean
    }
}

// MARK: - Builder Card View

public struct AICustomActionBuilderCard: View {
    @ObservedObject private var aiManager = AIServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    private enum BuilderPhase: Equatable {
        case idle
        case generating(prompt: String)
        case result
        case error(message: String)
    }

    @SwiftUI.State private var phase: BuilderPhase = .idle
    @SwiftUI.State private var promptInput: String = ""
    @SwiftUI.State private var synthesis: AICustomActionSynthesis = AICustomActionSynthesis(
        title: "",
        description: "",
        iconSymbol: "wand.and.stars",
        kind: "javascript",
        scriptCode: "",
        delivery: .replace
    )
    @SwiftUI.State private var isEditingCode: Bool = false
    @SwiftUI.State private var codeDraft: String = ""
    @SwiftUI.State private var showSuccessBadge: Bool = false
    @SwiftUI.State private var generationTask: Task<Void, Never>?
    @FocusState private var isPromptFocused: Bool

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .idle:
                idlePromptView
            case .generating(let prompt):
                generatingView(prompt: prompt)
            case .result:
                resultCardView
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private var idlePromptView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showSuccessBadge {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "Action Added"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.green)
                }
                .transition(.opacity.combined(with: .scale))
            }

            if !aiManager.isAIEnabled {
                HStack(spacing: 8) {
                    Text(String(localized: "AI is currently disabled."))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsDesignTokens.secondaryText)
                    Button(String(localized: "Enable in AI Settings")) {
                        router.push(.ai)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.link)
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Multiline Text Area (at least 3 lines)
                    ZStack(alignment: .topTrailing) {
                        TextField(
                            "",
                            text: $promptInput,
                            prompt: Text(String(localized: "Describe what to create (e.g. Format JSON)")),
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .lineLimit(3...8)
                        .labelsHidden()
                        .focused($isPromptFocused)
                        .padding(.trailing, promptInput.isEmpty ? 0 : 20)

                        if !promptInput.isEmpty {
                            Button {
                                promptInput = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsDesignTokens.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Clear"))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 72, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        isPromptFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                    )

                    // Bottom Row: 2 normal examples on left, Liquid Glass Generate button on right
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            suggestionChip(String(localized: "Format JSON"), prompt: "Format and pretty-print JSON")
                            suggestionChip(String(localized: "Extract URLs"), prompt: "Extract all URLs from text")
                        }

                        Spacer()

                        generateButton
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        if #available(macOS 26.0, *) {
            Button {
                startGeneration()
            } label: {
                Label(String(localized: "Generate"), systemImage: "sparkle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.glassButtonBlue)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: .capsule)
            .glassEffect(.regular.tint(SettingsDesignTokens.glassButtonBlue.opacity(0.18)).interactive(), in: .capsule)
            .contentShape(Capsule())
            .keyboardShortcut(.return, modifiers: .command)
        } else {
            Button {
                startGeneration()
            } label: {
                Label(String(localized: "Generate"), systemImage: "sparkle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func suggestionChip(_ label: String, prompt: String) -> some View {
        Button {
            promptInput = prompt
            startGeneration()
        } label: {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesignTokens.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .settingsGlassCapsule()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func generatingView(prompt: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Synthesizing action…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.primaryText)

                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button(String(localized: "Cancel")) {
                generationTask?.cancel()
                generationTask = nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    phase = .idle
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(SettingsDesignTokens.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .settingsGlassCapsule()
            .contentShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var resultCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon + Title + Engine Badge
            HStack(spacing: 10) {
                SettingsIconTile(
                    systemImage: synthesis.iconSymbol,
                    tint: SettingsDesignTokens.iconTileColor(forSystemImage: synthesis.iconSymbol),
                    size: 32
                )

                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "",
                        text: $synthesis.title,
                        prompt: Text(String(localized: "Action Title"))
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .labelsHidden()

                    if !synthesis.description.isEmpty {
                        Text(synthesis.description)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsDesignTokens.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Engine Pill
                Text(engineLabel(for: synthesis.kind))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }

            // Inferred Behavior Pills (One-tap switcher)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "BEHAVIOR"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SettingsDesignTokens.tertiaryText)

                HStack(spacing: 6) {
                    ForEach(AIActionDeliveryMode.allCases, id: \.self) { mode in
                        let isSelected = (synthesis.delivery == mode)
                        Button {
                            synthesis.delivery = mode
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 10))
                                Text(mode.label)
                                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                            }
                            .foregroundStyle(isSelected ? SettingsDesignTokens.primaryText : SettingsDesignTokens.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Mini Code Peek (2-3 lines styled preview or expanded editor)
            if !synthesis.scriptCode.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(synthesis.kind == "shell" ? "SHELL SCRIPT" : "JAVASCRIPT (JSC)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SettingsDesignTokens.tertiaryText)

                        Spacer()

                        Button(isEditingCode ? String(localized: "Done") : String(localized: "Edit Code ↗")) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if !isEditingCode {
                                    codeDraft = synthesis.scriptCode
                                } else {
                                    synthesis.scriptCode = codeDraft
                                }
                                isEditingCode.toggle()
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.link)
                    }

                    if isEditingCode {
                        TextEditor(text: $codeDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 120)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    } else {
                        miniCodeBox(code: synthesis.scriptCode)
                    }
                }
            }

            Divider()
                .padding(.vertical, 2)

            // Actions Bar
            HStack(spacing: 8) {
                Button(String(localized: "Discard")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        phase = .idle
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(SettingsDesignTokens.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .settingsGlassCapsule()
                .contentShape(Capsule())

                Spacer()

                if #available(macOS 26.0, *) {
                    Button {
                        saveAction()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(String(localized: "Add Action"))
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.glassButtonBlue)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: .capsule)
                    .glassEffect(.regular.tint(SettingsDesignTokens.glassButtonBlue.opacity(0.18)).interactive(), in: .capsule)
                    .contentShape(Capsule())
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button {
                        saveAction()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(String(localized: "Add Action"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func miniCodeBox(code: String) -> some View {
        let lines = code.components(separatedBy: "\n").prefix(3)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SettingsDesignTokens.tertiaryText)
                        .frame(width: 14, alignment: .trailing)

                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SettingsDesignTokens.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "Unable to Generate Action"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SettingsDesignTokens.secondaryText)

            HStack(spacing: 8) {
                Button(String(localized: "Try Again")) {
                    startGeneration()
                }
                .controlSize(.small)

                Button(String(localized: "Dismiss")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        phase = .idle
                    }
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logic

    private func startGeneration() {
        let trimmed = promptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            phase = .generating(prompt: trimmed)
        }

        generationTask?.cancel()
        generationTask = Task {
            do {
                let result = try await AICustomActionService.generate(userPrompt: trimmed)
                guard !Task.isCancelled, phase == .generating(prompt: trimmed) else { return }
                self.synthesis = result
                self.codeDraft = result.scriptCode
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    phase = .result
                }
            } catch {
                guard !Task.isCancelled, phase == .generating(prompt: trimmed) else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    phase = .error(message: error.localizedDescription)
                }
            }
        }
    }

    private func saveAction() {
        let currentSynthesis = isEditingCode ? AICustomActionSynthesis(
            title: synthesis.title,
            description: synthesis.description,
            iconSymbol: synthesis.iconSymbol,
            kind: synthesis.kind,
            scriptCode: codeDraft,
            urlTemplate: synthesis.urlTemplate,
            delivery: synthesis.delivery,
            isAsync: synthesis.isAsync
        ) : synthesis

        let id = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        let title = currentSynthesis.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Action" : currentSynthesis.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = currentSynthesis.iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "wand.and.stars" : currentSynthesis.iconSymbol

        let replaceSelection = (currentSynthesis.delivery == .replace)
        let actionType: CustomActionType
        switch currentSynthesis.kind {
        case "url":
            actionType = .openURL(urlTemplate: currentSynthesis.urlTemplate ?? currentSynthesis.scriptCode)
        case "textsnippet", "snippet":
            actionType = .textSnippet(template: currentSynthesis.scriptCode)
        case "shell":
            actionType = .shellScript(script: currentSynthesis.scriptCode, replaceSelection: replaceSelection)
        default: // javascript
            actionType = .javaScript(script: currentSynthesis.scriptCode, isAsync: currentSynthesis.isAsync, replaceSelection: replaceSelection)
        }

        let newAction = CustomAction(
            id: id,
            title: title,
            iconName: icon,
            type: actionType
        )

        ActionCoordinator.shared.saveCustomAction(newAction)
        _ = try? CustomActionManifestWriter.write(action: newAction)

        // Persist the chosen Behavior for this action id; without it Copy and Show save the same
        // action (the manifest only carries `replaceSelection`) and the choice is lost.
        let deliveryPreference: ResultDeliveryPreference?
        switch currentSynthesis.delivery {
        case .replace: deliveryPreference = nil
        case .copy: deliveryPreference = .copy
        case .preview: deliveryPreference = .preview
        }
        ActionCustomizationManager.shared.setDeliveryPreference(deliveryPreference, for: id)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            phase = .idle
            promptInput = ""
            showSuccessBadge = true
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.2)) {
                showSuccessBadge = false
            }
        }
    }

    private func engineLabel(for kind: String) -> String {
        switch kind {
        case "url": return "URL"
        case "shell": return "Shell"
        case "textsnippet": return "Snippet"
        default: return "JavaScript"
        }
    }
}
