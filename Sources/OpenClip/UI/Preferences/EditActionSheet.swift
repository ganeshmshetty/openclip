// EditActionSheet.swift
// OpenClip
//
// Renders the modal sheet interface for editing existing action appearances, titles, and parameters.
// For non-builtin actions (extension packages — including GUI-authored com.custom.<id> packages) it
// acts as a manifest reader/writer: the Appearance tab edits title/icon in the manifest, the General
// tab edits the target action's type/logic fields, and saving rewrites the manifest then reloads the
// extension list. Builtin actions keep the legacy ActionCustomizationManager appearance overrides.
// A non-builtin action whose manifest can't be located on disk (e.g. a standalone snippet script
// file) is read-only: the sheet surfaces why and disables Save rather than silently dropping edits.
// When opened via a ConfigurationRequest (missing-required-options short-circuit), a reason banner
// appears above the tabs and the missing option rows are highlighted in the General tab (Phase 7).
import SwiftUI
import AppKit
import Core

@MainActor
public struct EditActionSheet: View {
    let action: any Action
    /// Optional request from the action (e.g. a missing-required-options short-circuit): surfaces a
    /// reason banner and highlights the missing option rows in the unified editor (Phase 7).
    let configurationRequest: ConfigurationRequest?
    @Environment(\.dismiss) private var dismiss
    
    @State private var activeTab: Int = 0 // 0 = Appearance, 1 = General
    @State private var customTitle: String = ""
    @State private var iconSymbol: String = ""
    @State private var initialIconSymbol: String = ""
    /// Icon-symbol customization stored before the sheet opened (nil = none). An untouched icon
    /// field round-trips this on Save instead of writing the picker's baseline, so title-only
    /// edits can't clobber package-file / remote-image / text-glyph icons.
    @State private var initialStoredSymbol: String? = nil
    /// The action's effective real icon while no replacement has been picked from the picker;
    /// drives the honest preview in the Appearance fields.
    @State private var baseIconState: ActionIcon? = nil
    /// Set by Reset Name & Icon; the persisted override is cleared on Save (not immediately), so
    /// Cancel still backs out of an accidental reset.
    @State private var appearanceResetPending = false
    @State private var displayMode: Int = 0 // 0 = Icon, 1 = Text
    @State private var showingIconPicker: Bool = false
    
    // Custom Action State
    @State private var customType: CustomActionType = .textSnippet(template: "{text}")
    @State private var customURLTemplate: String = "https://www.google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "{text}"
    @State private var customShellScript: String = "echo $OPENCLIP_TEXT"
    @State private var replaceSelection: Bool = true
    
    // Manifest-backed state: the target action lives in an extension manifest package.
    @State private var manifestState: LocatedManifest?
    @State private var logicEditable: Bool = false
    // True when a non-builtin action has no locatable manifest (standalone script file), so the
    // sheet must stay read-only instead of dropping edits on Save.
    @State private var manifestMissing: Bool = false
    @State private var showingSaveAlert: Bool = false
    @State private var saveAlertMessage: String = ""
    
    public init(action: any Action, configurationRequest: ConfigurationRequest? = nil) {
        self.action = action
        self.configurationRequest = configurationRequest
    }
    
    private var isBuiltin: Bool {
        ActionIdentity.isBuiltin(action)
    }

    /// Banner text when the sheet was opened because the action needs configuration. Falls back to a
    /// generic message when the request has no reason but does name missing options.
    private var configurationBannerText: String? {
        guard let configurationRequest else { return nil }
        if let reason = configurationRequest.reason, !reason.isEmpty { return reason }
        if !configurationRequest.missingOptionIDs.isEmpty {
            return "This action needs configuration before it can run."
        }
        return nil
    }
    
    private var saveDisabled: Bool {
        !isBuiltin && manifestState == nil
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

            if let bannerText = configurationBannerText {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(bannerText)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if activeTab == 0 {
                        // Appearance Tab
                        VStack(alignment: .leading, spacing: 14) {
                            ActionAppearanceFields(
                                title: $customTitle,
                                displayTextFallback: action.title,
                                iconSymbol: $iconSymbol,
                                initialIconSymbol: initialIconSymbol,
                                baseIcon: baseIconState,
                                displayMode: $displayMode
                            )
                            
                            Button("Reset Name & Icon to Default") {
                                resetAppearance()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                            .padding(.top, 4)
                        }
                        .disabled(manifestMissing)
                    } else {
                        // General Tab (Behavior & Logic)
                        if !action.actionOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Action Options")
                                    .font(.headline)
                                DynamicActionConfigView(
                                    actionID: action.id,
                                    options: action.actionOptions,
                                    optionStore: SecretActionOptionStore(),
                                    missingOptionIDs: Set(configurationRequest?.missingOptionIDs ?? [])
                                )
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
                                if manifestMissing {
                                    Text("This action is a standalone script file with no editable manifest. Delete it and re-create it as a snippet or extension package to customize its behavior, name, or icon.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Standard action. Execution behavior and options are managed automatically by OpenClip.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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
                        if await saveChanges() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
            }
            .padding(12)
        }
        .frame(width: 340, height: 360)
        .alert("Unable to Save Changes", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveAlertMessage)
        }
        .onAppear {
            loadInitialState()
        }
    }
    
    // MARK: - Manifest lookup

    /// Locates the manifest package whose identifier matches the action's chrome source (or, as a
    /// fallback for stray `.custom` actions, its id) and returns the target action's edit state.
    /// Only directory-backed manifest packages are considered; a standalone script file with the
    /// same identifier returns nil, which the sheet treats as a read-only, uneditable action.
    static func locateManifest(for action: any Action, in directory: URL = Constants.extensionsDirectory) -> LocatedManifest? {
        ExtensionManifestStore.locateManifest(for: action, in: directory)
    }
    
    // MARK: - State loading
    
    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)

        customTitle = override?.customTitle ?? action.title
        initialStoredSymbol = Self.sanitizedStoredSymbol(override?.customIconSymbol, actionIcon: action.icon)
        seedBaseline(from: ActionCustomizationManager.shared.popupIcon(for: action))

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
            manifestMissing = false
            if let customAction = action as? CustomAction {
                loadCustomType(from: customAction)
            }
            return
        }
        
        manifestState = Self.locateManifest(for: action)
        guard let state = manifestState else {
            // Standalone-script action (or a stray non-builtin with no manifest on disk): the JSON
            // manifest is the only editable surface, so there is nothing to write. Keep the sheet
            // read-only and disable Save rather than silently dropping edits.
            logicEditable = false
            manifestMissing = true
            return
        }
        manifestMissing = false
        
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
    
    /// Seeds the icon editor from an effective icon: symbol-representable icons become the editable
    /// string baseline; package-file / remote-image / text-glyph icons stay out of the string field
    /// ("" = untouched) and are previewed via `baseIconState` instead of a placeholder symbol.
    private func seedBaseline(from icon: ActionIcon) {
        if case .symbol(let sym) = icon {
            iconSymbol = sym
            baseIconState = nil
        } else {
            iconSymbol = ""
            baseIconState = icon
        }
        initialIconSymbol = iconSymbol
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
        // Editors-only reset: persisted overrides/manifest are cleared on Save, so Cancel still
        // backs out of an accidental reset.
        appearanceResetPending = true
        initialStoredSymbol = nil
        seedBaseline(from: action.icon)
        if case .text = action.icon {
            displayMode = 1
        } else {
            displayMode = 0
        }
        customTitle = action.title
    }

    // MARK: - Saving

    private func saveChanges() async -> Bool {
        if appearanceResetPending {
            ActionCustomizationManager.shared.resetOverride(for: action.id)
            appearanceResetPending = false
        } else {
            saveAppearanceOverride()
        }
        if isBuiltin {
            return true
        }
        return await saveManifestChanges()
    }

    private func saveAppearanceOverride() {
        let titleOverride: String? = (customTitle.isEmpty || customTitle == action.title) ? nil : customTitle
        let symbolOverride = Self.resolvedSymbolOverride(
            current: iconSymbol,
            initial: initialIconSymbol,
            stored: initialStoredSymbol
        )
        let textOverride: String? = (displayMode == 1) ? (customTitle.isEmpty ? action.title : customTitle) : nil

        ActionCustomizationManager.shared.setOverride(
            for: action.id,
            title: titleOverride,
            symbol: symbolOverride,
            text: textOverride
        )
    }

    // MARK: - Appearance save decisions (pure, unit-tested)

    /// Symbol value to persist for the icon field. A genuinely user-picked change wins; an untouched
    /// field round-trips whatever was stored before (nil when there was none), so editing only the
    /// title never rewrites the icon.
    static func resolvedSymbolOverride(current: String, initial: String, stored: String?) -> String? {
        guard current.isEmpty || current == initial else { return current }
        return stored
    }

    /// Overrides written before the icon-clobber fix stored a literal "star" placeholder for every
    /// non-symbol-representable icon. Treat those as absent so the next Save heals them; a genuine
    /// "star" pick is kept only when the action's own icon already is that symbol.
    static func sanitizedStoredSymbol(_ raw: String?, actionIcon: ActionIcon) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == legacyFallbackSymbol {
            if case .symbol(let sym) = actionIcon, sym == legacyFallbackSymbol { return raw }
            return nil
        }
        return raw
    }

    private static let legacyFallbackSymbol = "star"

    
    private func saveManifestChanges() async -> Bool {
        guard let state = manifestState else {
            // Defensive: the Save button is disabled in this state, but if reached anyway (e.g. a
            // keyboard path) surface the reason instead of silently returning with edits dropped.
            saveAlertMessage = "This action is backed by a standalone script file with no editable manifest, so changes cannot be saved here."
            showingSaveAlert = true
            return false
        }
        
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
            isAsync: meta.isAsync,
            options: meta.options,
            subActions: meta.subActions,
            keyPress: meta.keyPress,
            serviceName: meta.serviceName,
            shortcutName: meta.shortcutName,
            menuRelevance: meta.menuRelevance,
            loading: meta.loading,
            loadingMessage: meta.loadingMessage,
            secondary: meta.secondary,
            toast: meta.toast,
            secondaryToast: meta.secondaryToast
        )
        
        var actions = state.manifest.actions
        actions[state.targetIndex] = updatedMeta
        let updatedManifest = ExtensionMetadata(
            identifier: state.manifest.identifier,
            name: state.manifest.name,
            actions: actions,
            options: state.manifest.options,
            version: state.manifest.version,
            capabilities: state.manifest.capabilities
        )
        
        do {
            try ExtensionManifestStore.writeManifest(updatedManifest, to: state.manifestURL)
        } catch {
            Log.factory.error("Failed to save action manifest: \(error.localizedDescription)")
            saveAlertMessage = "Failed to save the action manifest: \(error.localizedDescription)"
            showingSaveAlert = true
            return false
        }
        
        // Re-enable/re-trust package with its newly computed fingerprint so tamper detection
        // does not falsely flag authorized preferences edits.
        await ExtensionManager.shared.enablePackage(packageID: state.manifest.identifier)
        return true
    }
}
