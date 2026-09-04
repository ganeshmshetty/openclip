// EditActionSheet.swift
// OpenClip
//
// Renders the modal sheet / popover interface for editing existing action appearances, titles, and parameters.
// Styled in macOS Inset Grouped layout with Hero Header: content-hugging height, solid opaque background,
// and conditional options/logic display (omitting redundant info notes when no config options exist).
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

    // Custom Action State. The Type picker selects a plain kind — the payload values live in the
    // field state below — so the segment highlight stays stable while the user edits text (a
    // CustomActionType selection would embed the live string and unhighlight on every keystroke).
    private enum EditKind: Hashable {
        case webSearch
        case textSnippet
        case shellScript
    }
    @State private var editKind: EditKind = .textSnippet
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
            return String(localized: "This action needs configuration before it can run.")
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
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Content Area (fits content dynamically)
            VStack(alignment: .leading, spacing: 12) {
                if let bannerText = configurationBannerText {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
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
                }

                // Hero Header Card (Icon, Name & Display Mode)
                InsetGroupCard {
                    ActionAppearanceFields(
                        title: $customTitle,
                        displayTextFallback: action.title,
                        iconSymbol: $iconSymbol,
                        initialIconSymbol: initialIconSymbol,
                        baseIcon: baseIconState,
                        displayMode: $displayMode
                    )
                }
                .disabled(manifestMissing)

                // Options Section (shown only when the action declares configurable options)
                if !action.actionOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OPTIONS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        InsetGroupCard {
                            DynamicActionConfigView(
                                actionID: action.id,
                                options: action.actionOptions,
                                optionStore: SecretActionOptionStore(),
                                missingOptionIDs: Set(configurationRequest?.missingOptionIDs ?? [])
                            )
                        }
                    }
                } else if logicEditable {
                    // Execution Logic Section (GUI-authored custom actions only)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXECUTION LOGIC")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)

                        InsetGroupCard {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 12) {
                                    Text("Type")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Picker("Type", selection: $editKind) {
                                        Text("Web Search").tag(EditKind.webSearch)
                                        Text("Text Snippet").tag(EditKind.textSnippet)
                                        Text("Shell Script").tag(EditKind.shellScript)
                                    }
                                    .pickerStyle(.segmented)
                                    .labelsHidden()
                                    .frame(width: 240)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                Divider()
                                    .padding(.horizontal, 12)

                                Group {
                                    switch editKind {
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
                                                .scrollContentBackground(.hidden)
                                                .padding(6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(Color.primary.opacity(0.04))
                                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12)))
                                                )
                                        }
                                    case .shellScript:
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Shell Script (Zsh)").font(.caption).foregroundColor(.secondary)
                                            TextEditor(text: $customShellScript)
                                                .font(.system(.body, design: .monospaced))
                                                .frame(height: 90)
                                                .scrollContentBackground(.hidden)
                                                .padding(6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(Color.primary.opacity(0.04))
                                                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12)))
                                                )

                                            Toggle("Replace selected text with output", isOn: $replaceSelection)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                        }
                    }
                } else if manifestMissing {
                    // Warning only when manifest is truly unlocatable / standalone script
                    InsetGroupCard {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                                .padding(.top, 1)

                            Text("This action is a standalone script file with no editable manifest. Re-create it as an extension package to customize its behavior.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                    }
                }
            }
            .padding(14)

            Divider()

            // Footer Action Buttons
            HStack(spacing: 12) {
                Button("Reset to Default") {
                    resetAppearance()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
                .disabled(manifestMissing)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save Changes") {
                    Task {
                        if await saveChanges() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 370)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
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

        // Raw execution-logic editing (type/URL/script) is a GUI-authored-action surface only:
        // com.custom.<id> packages keep the editor, while store and developer extension packages
        // stay read-only in the General tab — their behavior belongs to the package, and an
        // accidental rewrite here would silently mutate an installed third-party extension.
        guard state.manifest.identifier.hasPrefix(Constants.customIdentifierPrefix) else {
            logicEditable = false
            return
        }
        let meta = state.manifest.actions[state.targetIndex]
        switch meta.kind {
        case .url, .webSearch:
            customURLTemplate = meta.url ?? ""
            editKind = .webSearch
            logicEditable = true
        case .textSnippet:
            customSnippetTemplate = meta.scriptCode ?? ""
            editKind = .textSnippet
            logicEditable = true
        case .shellInline:
            customShellScript = meta.scriptCode ?? ""
            editKind = .shellScript
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
        switch customAction.type {
        case .webSearch(let url):
            editKind = .webSearch
            customURLTemplate = url
        case .textSnippet(let snippet):
            editKind = .textSnippet
            customSnippetTemplate = snippet
        case .shellScript(let script, let replace):
            editKind = .shellScript
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
            saveAlertMessage = String(localized: "This action is backed by a standalone script file with no editable manifest, so changes cannot be saved here.")
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
            switch editKind {
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
            secondaryToast: meta.secondaryToast,
            keywords: meta.keywords,
            localizedTitle: (finalTitle.isEmpty || finalTitle == meta.title || finalTitle == meta.localizedTitle?.resolve()) ? meta.localizedTitle : nil,
            localizedLoadingMessage: meta.localizedLoadingMessage
        )

        var actions = state.manifest.actions
        actions[state.targetIndex] = updatedMeta
        let updatedManifest = ExtensionMetadata(
            identifier: state.manifest.identifier,
            name: state.manifest.name,
            actions: actions,
            options: state.manifest.options,
            version: state.manifest.version,
            capabilities: state.manifest.capabilities,
            minOpenClipVersion: state.manifest.minOpenClipVersion,
            keywords: state.manifest.keywords,
            localizedName: state.manifest.localizedName,
            description: state.manifest.description,
            localizedDescription: state.manifest.localizedDescription
        )

        do {
            try ExtensionManifestStore.writeManifest(updatedManifest, to: state.manifestURL)
        } catch {
            Log.factory.error("Failed to save action manifest: \(error.localizedDescription)")
            saveAlertMessage = String(localized: "Failed to save the action manifest: \(error.localizedDescription)")
            showingSaveAlert = true
            return false
        }

        // Re-trust the package with its newly computed fingerprint so tamper detection does not
        // falsely flag authorized preferences edits — but only if it was already trusted: a
        // revoked or never-enabled package keeps its trust state (an edit save is not consent).
        await ExtensionManager.shared.retrustAfterAuthorizedEdit(packageID: state.manifest.identifier)
        return true
    }
}

// MARK: - Inset Group Card Container

private struct InsetGroupCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}
