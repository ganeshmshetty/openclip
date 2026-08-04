// EditActionSheet.swift
// OpenClip
//
// Renders the modal sheet interface for editing existing action appearances, titles, and parameters.
// For non-builtin actions (extension packages — including GUI-authored com.custom.<id> packages) it
// acts as a manifest reader/writer: the Appearance tab edits title/icon in the manifest, the General
// tab edits the target action's type/logic fields, and saving rewrites the manifest then reloads the
// extension list. Builtin actions keep the legacy ActionCustomizationManager appearance overrides.
import SwiftUI
import AppKit
import Core

@MainActor
public struct EditActionSheet: View {
    let action: any Action
    @Environment(\.dismiss) private var dismiss
    
    @State private var activeTab: Int = 0 // 0 = Appearance, 1 = General
    @State private var customTitle: String = ""
    @State private var iconSymbol: String = ""
    @State private var initialIconSymbol: String = ""
    @State private var displayMode: Int = 0 // 0 = Icon, 1 = Text
    @State private var showingIconPicker: Bool = false
    
    // Custom Action State
    @State private var customType: CustomActionType = .textSnippet(template: "{text}")
    @State private var customURLTemplate: String = "https://www.google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "{text}"
    @State private var customShellScript: String = "echo $OPENCLIP_TEXT"
    @State private var replaceSelection: Bool = true
    
    // Manifest-backed state: the target action lives in an extension manifest package.
    private struct ManifestEditState {
        let manifestURL: URL
        let manifest: ExtensionMetadata
        let targetIndex: Int
    }
    @State private var manifestState: ManifestEditState?
    @State private var logicEditable: Bool = false
    
    private let popularSymbols = [
        "magnifyingglass", "doc.on.doc", "scissors", "folder",
        "sparkles", "link", "character.cursor", "square.and.arrow.up",
        "textformat", "globe", "terminal", "gearshape"
    ]
    
    public init(action: any Action) {
        self.action = action
    }
    
    private var isBuiltin: Bool {
        if case .builtin = action.chrome.source { return true }
        return false
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Action")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Picker("", selection: $activeTab) {
                Label("Appearance", systemImage: "paintpalette").tag(0)
                Label("General", systemImage: "gearshape").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if activeTab == 0 {
                        // Appearance Tab
                        VStack(alignment: .leading, spacing: 14) {
                            ActionAppearanceFields(
                                title: $customTitle,
                                iconSymbol: $iconSymbol,
                                displayMode: $displayMode
                            )
                            
                            Button("Reset Name & Icon to Default") {
                                resetAppearance()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                            .padding(.top, 4)
                        }
                    } else {
                        // General Tab (Behavior & Logic)
                        if !action.actionOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Action Options")
                                    .font(.headline)
                                DynamicActionConfigView(actionID: action.id, options: action.actionOptions)
                            }
                        } else if logicEditable {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Action Type & Execution Logic")
                                    .font(.headline)
                                
                                Picker("Type", selection: $customType) {
                                    Text("Web Search").tag(CustomActionType.webSearch(urlTemplate: customURLTemplate))
                                    Text("Text Snippet").tag(CustomActionType.textSnippet(template: customSnippetTemplate))
                                    Text("Shell Script").tag(CustomActionType.shellScript(script: customShellScript, replaceSelection: replaceSelection))
                                }
                                .pickerStyle(.segmented)
                                
                                switch customType {
                                case .webSearch:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("URL Template").font(.caption).foregroundColor(.secondary)
                                        TextField("https://example.com/search?q={text}", text: $customURLTemplate)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                case .textSnippet:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Snippet Template").font(.caption).foregroundColor(.secondary)
                                        TextEditor(text: $customSnippetTemplate)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 70)
                                            .border(Color.secondary.opacity(0.2))
                                    }
                                case .shellScript:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Shell Script (Zsh)").font(.caption).foregroundColor(.secondary)
                                        TextEditor(text: $customShellScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 90)
                                            .border(Color.secondary.opacity(0.2))
                                        
                                        Toggle("Replace selected text with output", isOn: $replaceSelection)
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("General Action Information")
                                    .font(.headline)
                                Text("Standard action. Execution behavior and options are managed automatically by OpenClip.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // Footer Action Buttons
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Changes") {
                    Task {
                        await saveChanges()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 340, height: 360)
        .onAppear {
            loadInitialState()
        }
    }
    
    // MARK: - Manifest lookup
    
    /// Locates the manifest package whose identifier matches the action's chrome source (or, as a
    /// fallback for stray `.custom` actions, its id) and returns the target action's edit state.
    private static func locateManifest(for action: any Action) -> ManifestEditState? {
        let packageID: String
        if case .extensionPkg(let pid) = action.chrome.source {
            packageID = pid
        } else {
            packageID = action.id
        }
        let directory = Constants.extensionsDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        let manifestNames = [Constants.manifestFileName, Constants.legacyManifestFileName, "Config.json"]
        for item in items {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
            for name in manifestNames {
                let manifestURL = item.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(ExtensionMetadata.self, from: data),
                      manifest.identifier == packageID else { continue }
                for (index, meta) in manifest.actions.enumerated()
                where ExtensionManager.uniformActionID(metadata: meta, manifest: manifest, index: index) == action.id {
                    return ManifestEditState(manifestURL: manifestURL, manifest: manifest, targetIndex: index)
                }
            }
        }
        return nil
    }
    
    // MARK: - State loading
    
    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)
        
        customTitle = override?.customTitle ?? action.title
        if let sym = override?.customIconSymbol, !sym.isEmpty {
            iconSymbol = sym
        } else if case .symbol(let sym) = action.icon {
            iconSymbol = sym
        } else {
            iconSymbol = "star"
        }
        initialIconSymbol = iconSymbol
        
        if override?.customIconText != nil {
            displayMode = 1
        } else if case .text = action.icon {
            displayMode = 1
        } else {
            displayMode = 0
        }
        
        if isBuiltin {
            manifestState = nil
            logicEditable = false
            if let customAction = action as? CustomAction {
                loadCustomType(from: customAction)
            }
            return
        }
        
        manifestState = Self.locateManifest(for: action)
        guard let state = manifestState else {
            // Stray non-builtin action with no manifest on disk: fall back to the in-memory type.
            logicEditable = false
            if let customAction = action as? CustomAction {
                loadCustomType(from: customAction)
            }
            return
        }
        
        let meta = state.manifest.actions[state.targetIndex]
        switch meta.kind {
        case .url, .webSearch:
            customType = .webSearch(urlTemplate: customURLTemplate)
            customURLTemplate = meta.url ?? ""
            logicEditable = true
        case .textSnippet:
            customType = .textSnippet(template: customSnippetTemplate)
            customSnippetTemplate = meta.scriptCode ?? ""
            logicEditable = true
        case .shellInline:
            customType = .shellScript(script: customShellScript, replaceSelection: replaceSelection)
            customShellScript = meta.scriptCode ?? ""
            logicEditable = true
        default:
            logicEditable = false
        }
    }
    
    private func loadCustomType(from customAction: CustomAction) {
        customType = customAction.type
        switch customAction.type {
        case .webSearch(let url): customURLTemplate = url
        case .textSnippet(let snippet): customSnippetTemplate = snippet
        case .shellScript(let script, let replace):
            customShellScript = script
            replaceSelection = replace
        }
    }
    
    private func resetAppearance() {
        if isBuiltin {
            ActionCustomizationManager.shared.resetOverride(for: action.id)
        }
        // Manifest-backed and builtin both re-read current on-disk state, discarding unsaved edits.
        loadInitialState()
    }
    
    // MARK: - Saving
    
    private func saveChanges() async {
        if isBuiltin {
            saveBuiltinOverride()
            return
        }
        await saveManifestChanges()
    }
    
    private func saveBuiltinOverride() {
        let titleOverride: String? = (customTitle.isEmpty || customTitle == action.title) ? nil : customTitle
        let symbolOverride: String? = iconSymbol.isEmpty ? nil : iconSymbol
        let textOverride: String? = (displayMode == 1) ? (customTitle.isEmpty ? action.title : customTitle) : nil
        
        ActionCustomizationManager.shared.setOverride(
            for: action.id,
            title: titleOverride,
            symbol: symbolOverride,
            text: textOverride
        )
    }
    
    private func saveManifestChanges() async {
        guard let state = manifestState else { return }
        
        let meta = state.manifest.actions[state.targetIndex]
        let finalTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only rewrite the icon when the user actually changed it, so local-file icons on
        // extension actions aren't clobbered by the symbol-only fallback value.
        let finalIcon = (iconSymbol != initialIconSymbol && !iconSymbol.isEmpty) ? iconSymbol : meta.icon
        
        var newURL = meta.url
        var newType = meta.type
        var newScriptCode = meta.scriptCode
        if logicEditable {
            switch customType {
            case .webSearch:
                newURL = customURLTemplate
                newType = "url"
                newScriptCode = nil
            case .textSnippet:
                newURL = nil
                newType = "textsnippet"
                newScriptCode = customSnippetTemplate
            case .shellScript:
                newURL = nil
                newType = "shell"
                newScriptCode = customShellScript
            }
        }
        
        let updatedMeta = ExtensionActionMetadata(
            id: meta.id,
            title: finalTitle.isEmpty ? meta.title : finalTitle,
            icon: finalIcon,
            script: meta.script,
            url: newURL,
            regex: meta.regex,
            type: newType,
            scriptCode: newScriptCode,
            requirements: meta.requirements,
            after: meta.after,
            stayVisible: meta.stayVisible,
            options: meta.options,
            subActions: meta.subActions,
            keyPress: meta.keyPress,
            serviceName: meta.serviceName,
            shortcutName: meta.shortcutName
        )
        
        var actions = state.manifest.actions
        actions[state.targetIndex] = updatedMeta
        let updatedManifest = ExtensionMetadata(
            identifier: state.manifest.identifier,
            name: state.manifest.name,
            actions: actions,
            options: state.manifest.options
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updatedManifest)
            try data.write(to: state.manifestURL, options: .atomic)
        } catch {
            print("Failed to save action manifest: \(error)")
            return
        }
        
        // Manifest edits supersede any legacy appearance override for this action.
        ActionCustomizationManager.shared.resetOverride(for: action.id)
        await ExtensionManager.shared.loadExtensions()
    }
}
