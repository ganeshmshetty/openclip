// ActionEditorPage.swift
// OpenClip
//
// One action's settings as a Settings window page: appearance, keyboard (alias, hotkey), and the
// action's options or custom execution logic. Enable, duplicate and delete live in the toolbar and
// take effect without Save.
import SwiftUI
import AppKit
import Core
import KeyboardShortcuts

@MainActor
public struct ActionEditorPage: View {
    let action: any Action
    /// Built-in sidebar page: Cancel becomes Revert and Save stays on the page.
    let isSidebarPage: Bool
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @State private var isRenamingTitle = false
    @State private var titleBeforeRename = ""
    @FocusState private var heroNameFocused: Bool
    @State private var customTitle: String = ""
    @State private var iconSymbol: String = ""
    @State private var initialIconSymbol: String = ""
    /// Stored icon override before the page opened; an untouched icon field round-trips it on Save,
    /// so title-only edits can't clobber package-file, remote or text-glyph icons.
    @State private var initialStoredSymbol: String? = nil
    /// Real icon until a replacement is picked; drives the honest preview.
    @State private var baseIconState: ActionIcon? = nil
    /// Reset to Default clears the override only on Save, so Cancel can still undo it.
    @State private var appearanceResetPending = false
    @State private var displayMode: Int = 0 // 0 = Icon, 1 = Text
    @State private var isIconHovered = false
    @State private var isIconPickerPresented = false

    // The Type picker holds a plain kind, not the payload, so its highlight stays put while text is edited.
    private enum EditKind: Hashable {
        case openURL
        case textSnippet
        case shellScript
        case javaScript

        static let webSearch: EditKind = .openURL
    }
    @State private var editKind: EditKind = .textSnippet
    @State private var customURLTemplate: String = "https://www.google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "{text}"
    @State private var customShellScript: String = "echo $OPENCLIP_TEXT"
    @State private var customJavaScript: String = "function action(text) {\n    return text.toUpperCase();\n}"
    @State private var customJSIsAsync: Bool = false
    @State private var replaceSelection: Bool = true
    @State private var aiPrompt: String = ""
    @State private var isPromptExpanded = false
    @State private var aiProviderOverride: String?
    @State private var aiModelOverride: String?
    @State private var aiRequestsAdditionalInstruction = false

    // Manifest-backed state: the target action lives in an extension manifest package.
    @State private var manifestState: LocatedManifest?
    @State private var logicEditable: Bool = false
    // Non-builtin action with no locatable manifest (standalone script): stay read-only rather than drop edits.
    @State private var manifestMissing: Bool = false
    /// Why the last Save failed; shown inline above the buttons.
    @State private var saveErrorMessage: String?
    @State private var aliasText: String = ""
    @State private var aliasError: String? = nil
    @State private var isLoaded = false
    @State private var deliveryPrefString: String = "default"
    @State private var isDuplicating = false
    @State private var isDeleting = false
    @ObservedObject private var updateManager = ExtensionUpdateManager.shared
    @State private var isUpdating = false
    @State private var showUninstallConfirmation = false
    @State private var updateCheckState: UpdateCheckState = .idle

    private enum UpdateCheckState: Equatable {
        case idle
        case checking
        case upToDate
    }

    public init(
        action: any Action,
        isSidebarPage: Bool = false,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>
    ) {
        self.action = action
        self.isSidebarPage = isSidebarPage
        self._disabledActionIDs = disabledActionIDs
        self._disabledPackages = disabledPackages
        let initialDelivery: String
        if let pref = ActionCustomizationManager.shared.override(for: action.id)?.deliveryPreference {
            initialDelivery = pref.rawValue
        } else {
            initialDelivery = Self.defaultDeliveryPrefString(for: action)
        }
        _deliveryPrefString = State(initialValue: initialDelivery)
    }

    private var isCustomAction: Bool {
        SettingsDestination.isCustomAction(action)
    }

    private var isAIPreset: Bool {
        ActionIdentity.isAIPreset(action)
    }

    private var aiPreset: AIActionPreset? {
        guard isAIPreset else { return nil }
        return AIServiceManager.shared.preset(forActionID: action.id)
    }

    private var isCustomAIPreset: Bool {
        guard let aiPreset else { return false }
        return !AIServiceManager.defaultPresets.contains(where: { $0.id == aiPreset.id })
    }

    private var canDuplicate: Bool {
        ActionIdentity.canDuplicate(action)
    }

    /// True when this level of the stack is the one on screen.
    private var isCurrent: Bool {
        switch router.currentPage {
        case .action(let id), .builtinAction(let id): return id == action.id
        case .aiPreset(let id): return id == aiPreset?.id
        case .extensionPackage(let id):
            return ActionIdentity.extensionPackageID(of: action) == id
        default: return false
        }
    }

    private var isBuiltin: Bool {
        ActionIdentity.isBuiltin(action)
    }

    /// Request that opened this page from the popup because required options are unset.
    private var configurationRequest: ConfigurationRequest? {
        router.configurationRequest(for: action.id)
    }

    /// Leaves the page, or — on a sidebar page — stays and reloads it from what is saved.
    private func close() {
        router.clearConfigurationRequest(for: action.id)
        if isSidebarPage {
            saveErrorMessage = nil
            loadInitialState()
        } else {
            router.pop()
        }
    }

    /// Banner text for a configuration request; generic when it names missing options but gives no reason.
    private var configurationBannerText: String? {
        guard let configurationRequest else { return nil }
        if let reason = configurationRequest.reason, !reason.isEmpty { return reason }
        if !configurationRequest.missingOptionIDs.isEmpty {
            return String(localized: "This action needs configuration before it can run.")
        }
        return nil
    }

    private var saveDisabled: Bool {
        if action is CustomAction { return false }
        return !isBuiltin && manifestState == nil
    }

    private var heroFootnote: String {
        if ActionIdentity.isBuiltin(action) {
            return String(localized: "Built-in action")
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           let info = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions) {
            return info.name
        }
        if isCustomAction {
            return String(localized: "Custom Action")
        }
        return ""
    }

    /// Semantic tint of the action or its extension.
    private var heroTint: Color {
        if let packageID = ActionIdentity.extensionPackageID(of: action) {
            return SettingsTint.extensionTint(for: packageID)
        }
        return SettingsDesignTokens.iconTileColor(forActionID: action.id)
    }

    static func defaultDeliveryPrefString(for action: any Action) -> String {
        if let rec = action.chrome.recommendedResult {
            switch rec {
            case .preview: return "preview"
            case .paste, .pasteOrCopy: return "paste"
            case .copy: return "copy"
            case .open, .save: return "paste"
            }
        }
        if action.chrome.outputKind == .text {
            return "paste"
        }
        return "paste"
    }

    private var canProduceTextOutput: Bool {
        // AI presets stream through the controller's AI flow, not the ordinary delivery preference.
        if isAIPreset { return false }
        if action.chrome.outputKind == .text || action.chrome.outputKind == .dynamic {
            return true
        }
        if action.chrome.outputKind == .none || action.chrome.outputKind == .file {
            return false
        }
        if isBuiltin { return false }
        if action.chrome.launchesAI { return true }
        if action is CustomAction {
            return editKind != .openURL
        }
        if let state = manifestState,
           let meta = Self.targetMetadata(for: action.id, in: state) {
            switch meta.kind {
            case .textSnippet:
                return true
            case .url, .webSearch, .keyPress, .service, .shortcut, .group:
                return false
            case .applescript:
                if let code = Self.scriptContent(for: meta, in: state) {
                    return ScriptOutputSniffers.appleScriptProducesText(code: code)
                }
                return true
            case .shellInline, .scriptFile:
                if let code = Self.scriptContent(for: meta, in: state) {
                    return ScriptOutputSniffers.shellProducesText(code: code)
                }
                return true
            case .js:
                if let code = Self.scriptContent(for: meta, in: state) {
                    return ScriptOutputSniffers.jsProducesText(code: code)
                }
                return true
            }
        }
        let base = Self.unwrapBase(action)
        if let jsAction = base as? JavaScriptAction {
            return ScriptOutputSniffers.jsProducesText(code: jsAction.scriptCode)
        }
        if let asAction = base as? AppleScriptAction {
            return ScriptOutputSniffers.appleScriptProducesText(code: asAction.appleScriptCode)
        }
        if let scriptAction = base as? ScriptAction {
            if let content = try? String(contentsOf: scriptAction.scriptURL, encoding: .utf8) {
                return ScriptOutputSniffers.shellProducesText(code: content)
            }
            return true
        }
        return false
    }

    private var previewIcon: ActionIcon {
        ActionAppearanceFields.resolvedPreviewIcon(
            displayMode: 0,
            title: customTitle,
            displayTextFallback: action.title,
            iconSymbol: iconSymbol,
            initialIconSymbol: initialIconSymbol,
            baseIcon: baseIconState,
            textGlyphFallbackSymbol: Self.iconModeFallbackSymbol(for: action)
        )
    }

    private var iconButtonHelp: String {
        switch previewIcon {
        case .symbol(let name):
            return name.isEmpty ? String(localized: "Choose icon") : String(localized: "Icon: \(name) — click to change")
        case .text(let text):
            if displayMode == 1 {
                return String(localized: "Popup bar shows “\(text)” — click to choose the icon for icon mode")
            }
            return String(localized: "Text glyph “\(text)” — click to replace with an icon")
        case .url:
            return String(localized: "Remote image — click to replace with an icon")
        case .local(let url):
            if url.path.hasPrefix(Constants.customIconsDirectory.path) {
                return String(localized: "Custom icon “\(url.lastPathComponent)” — click to change")
            }
            return String(localized: "Package image “\(url.lastPathComponent)” — click to replace with an icon")
        }
    }

    private var actionEnabledBinding: Binding<Bool> {
        ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages
        )
    }

    private var extensionPackageID: String? {
        ActionIdentity.extensionPackageID(of: action)
    }

    private var manifest: ExtensionMetadata? {
        manifestState?.manifest ?? Self.locateManifest(for: action)?.manifest
    }

    private var manifestVersion: String? {
        manifest?.version
    }

    private var manifestAuthor: String? {
        manifest?.author
    }

    @ViewBuilder
    private var headerIconTile: some View {
        let size: CGFloat = 42
        let radius = SettingsDesignTokens.iconTileRadius(for: size)
        let squircle = RoundedRectangle(cornerRadius: radius, style: .continuous)

        ZStack {
            squircle
                .fill(SettingsTint.neutral)
                .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

            if case .text(let text) = previewIcon {
                Text(String(text.trimmingCharacters(in: .whitespaces).prefix(3)))
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                ActionIconView(icon: previewIcon, size: size * 0.56)
                    .foregroundStyle(.white)
                    .frame(width: size * 0.72, height: size * 0.72)
            }
        }
        .frame(width: size, height: size)
    }

    /// Destructive Delete control for custom actions and installed extensions.
    @ViewBuilder
    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        if #available(macOS 26.0, *) {
            Button(role: .destructive, action: action) {
                Label(String(localized: "Delete"), systemImage: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.glassButtonRed)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            }
            .buttonStyle(.plain)
            .settingsGlassCapsule(tint: SettingsDesignTokens.glassButtonRed.opacity(0.14), interactive: true)
            .contentShape(Capsule())
        } else {
            Button(role: .destructive, action: action) {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(Color.red)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func extensionUpdateStatusView(for packageID: String) -> some View {
        if isUpdating {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(String(localized: "Updating…"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
        } else if updateManager.updatablePackageIDs.contains(packageID) {
            if #available(macOS 26.0, *) {
                Button {
                    updateExtension(packageID)
                } label: {
                    Label(String(localized: "Update"), systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.glassButtonBlue)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .settingsGlassCapsule(tint: SettingsDesignTokens.glassButtonBlue.opacity(0.16), interactive: true)
                .contentShape(Capsule())
            } else {
                Button {
                    updateExtension(packageID)
                } label: {
                    Label(String(localized: "Update"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        } else if updateCheckState == .checking || updateManager.isChecking {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(String(localized: "Checking…"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
        } else if updateCheckState == .upToDate {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.green)
                Text(String(localized: "Up to date"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.12))
            )
            .transition(.opacity)
        } else {
            if #available(macOS 26.0, *) {
                Button {
                    runCheckForUpdates(packageID: packageID)
                } label: {
                    Label(String(localized: "Check for Updates"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .settingsGlassCapsule(interactive: true)
                .contentShape(Capsule())
            } else {
                Button {
                    runCheckForUpdates(packageID: packageID)
                } label: {
                    Label(String(localized: "Check for Updates"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.accentColor)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var upperHeroCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    headerIconTile

                    VStack(alignment: .leading, spacing: 3) {
                        let displayTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        HStack(alignment: .center, spacing: 8) {
                            if isRenamingTitle {
                                TextField("Action Name", text: $customTitle)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
                                    .frame(maxWidth: 280, alignment: .leading)
                                    .focused($heroNameFocused)
                                    .onAppear { heroNameFocused = true }
                                    .onSubmit { isRenamingTitle = false }
                                    .onExitCommand {
                                        customTitle = titleBeforeRename
                                        isRenamingTitle = false
                                    }
                                    .onChange(of: heroNameFocused) { _, focused in
                                        if !focused { isRenamingTitle = false }
                                    }
                            } else {
                                Text(displayTitle.isEmpty ? action.title : displayTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(SettingsDesignTokens.primaryText)
                                    .lineLimit(1)
                                    .onTapGesture(count: 2) {
                                        titleBeforeRename = customTitle
                                        isRenamingTitle = true
                                    }
                            }

                            if let version = manifestVersion, !version.isEmpty {
                                Text("v\(version)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(white: 1.0, opacity: 0.08)))
                            }

                        }
                    }

                    Spacer(minLength: 12)

                    Toggle("", isOn: actionEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                }
                if let packageID = extensionPackageID {
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 10)

                    HStack(alignment: .center) {
                        if let author = manifestAuthor, !author.isEmpty {
                            Text("by \(author)")
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsDesignTokens.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 12)

                        HStack(alignment: .center, spacing: 8) {
                            extensionUpdateStatusView(for: packageID)

                            deleteButton {
                                showUninstallConfirmation = true
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                } else if isCustomAction || isCustomAIPreset {
                    Divider()
                        .opacity(0.3)
                        .padding(.vertical, 10)

                    HStack(alignment: .center) {
                        Spacer(minLength: 12)

                        deleteButton {
                            confirmDelete()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
            .padding(.vertical, 12)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                upperHeroCard

                if let bannerText = configurationBannerText {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13))
                        Text(bannerText)
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                }

                SettingsCard("Appearance") {
                    SettingsRow(
                        title: "Icon",
                        subtitle: "Choose a custom symbol for the popup bar.",
                        systemImage: "app.dashed",
                        iconTileTint: heroTint,
                        plainIcon: true,
                        descriptionOnHover: true
                    ) {
                        Button {
                            isIconPickerPresented = true
                        } label: {
                            HStack(spacing: 6) {
                                ActionIconView(icon: previewIcon, size: 14)
                                    .foregroundStyle(SettingsDesignTokens.primaryText)
                                Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(manifestMissing)
                        .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                            IconPickerPopover(selectedSymbol: $iconSymbol) {
                                isIconPickerPresented = false
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Name",
                        subtitle: "Custom title shown in search and the popup bar.",
                        systemImage: "textformat",
                        iconTileTint: Color(red: 0.10, green: 0.74, blue: 0.66),
                        plainIcon: true,
                        descriptionOnHover: true
                    ) {
                        customNameField
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Show as",
                        subtitle: "Display as an icon or as text in the popup bar.",
                        systemImage: "rectangle.split.2x1",
                        iconTileTint: SettingsTint.customize,
                        plainIcon: true,
                        descriptionOnHover: true
                    ) {
                        Picker("", selection: $displayMode) {
                            Text("Icon").tag(0)
                            Text("Text").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(manifestMissing)
                    }
                }

                let hasTriggers = ActionIdentity.isBindable(action)
                let hasOutput = canProduceTextOutput
                if hasTriggers || hasOutput {
                    let cardTitle: LocalizedStringKey = (hasTriggers && hasOutput)
                        ? "Triggers & Output"
                        : (hasTriggers ? "Triggers" : "Output")

                    SettingsCard(cardTitle) {
                        if hasTriggers {
                            SettingsRow(
                                title: "Keyboard Shortcut",
                                subtitle: "Global hotkey to run this action directly.",
                                systemImage: "keyboard",
                                iconTileTint: SettingsDesignTokens.iconTileColor(forSystemImage: "keyboard"),
                                plainIcon: true,
                                descriptionOnHover: true
                            ) {
                                Shortcut(for: .actionHotkey(action.id))
                            }

                            SettingsDivider()

                            SettingsRow(
                                title: "Search Alias",
                                subtitle: "Keyword to jump to this action in the search palette.",
                                systemImage: "text.magnifyingglass",
                                iconTileTint: SettingsDesignTokens.iconTileColor(forSystemImage: "magnifyingglass"),
                                plainIcon: true,
                                descriptionOnHover: true
                            ) {
                                HStack(spacing: 8) {
                                    if let aliasError {
                                        Text(aliasError)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                    TextField("Alias", text: $aliasText, prompt: Text("e.g. tr"))
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 13))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color(white: 1.0, opacity: 0.08))
                                        )
                                        .frame(maxWidth: 100)
                                        .disabled(manifestMissing)
                                }
                            }
                        }

                        if hasTriggers && hasOutput {
                            SettingsDivider()
                        }

                        if hasOutput {
                            SettingsRow(
                                title: "When finished",
                                subtitle: "Where to send the output of this action.",
                                systemImage: "arrow.turn.down.right",
                                iconTileTint: SettingsDesignTokens.iconTileColor(forSystemImage: "arrow.turn.down.right"),
                                plainIcon: true,
                                descriptionOnHover: true
                            ) {
                                Picker("", selection: $deliveryPrefString) {
                                    Text("Show in card").tag("preview")
                                    Text("Paste").tag("paste")
                                    Text("Copy").tag("copy")
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 250)
                            }
                        }
                    }
                }

                if isAIPreset {
                    let promptIsEmpty = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let showsPrompt = isPromptExpanded || promptIsEmpty
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { isPromptExpanded.toggle() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .rotationEffect(.degrees(showsPrompt ? 90 : 0))
                                        .frame(width: 10)
                                    Text("Prompt Instruction")
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(isPromptExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
                            .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                            .padding(.top, SettingsDesignTokens.sectionCardPaddingV)
                            .padding(.bottom, showsPrompt ? 0 : SettingsDesignTokens.sectionCardPaddingV)

                            if showsPrompt {
                                AIPromptInstructionEditor(
                                    prompt: $aiPrompt,
                                    requestsAdditionalInstruction: $aiRequestsAdditionalInstruction,
                                    placeholder: String(localized: "Prompt instruction..."),
                                    showsEmptyPromptError: true
                                )
                            }
                        }
                    }
                }

                if isAIPreset {
                    AIPresetModelSection(provider: $aiProviderOverride, model: $aiModelOverride)
                }

                if !action.actionOptions.isEmpty {
                    SettingsCard("Options") {
                        VStack(spacing: 0) {
                            ForEach(Array(action.actionOptions.enumerated()), id: \.element.id) { index, option in
                                if index > 0 {
                                    SettingsDivider(insetLeading: SettingsDesignTokens.sectionCardPaddingH)
                                }
                                DynamicOptionRowView(
                                    actionID: action.id,
                                    option: option,
                                    optionStore: SecretActionOptionStore(),
                                    missingOptionIDs: Set(configurationRequest?.missingOptionIDs ?? [])
                                )
                                .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                                .padding(.vertical, SettingsDesignTokens.sectionCardPaddingV)
                            }
                        }
                    }
                }

                if logicEditable {
                    SettingsCard("Execution Logic") {
                        VStack(spacing: 12) {
                            SettingsRow(title: "Type") {
                                Picker("Type", selection: $editKind) {
                                    Text("Open URL").tag(EditKind.openURL)
                                    Text("Text Snippet").tag(EditKind.textSnippet)
                                    Text("Shell Script").tag(EditKind.shellScript)
                                    Text("JavaScript").tag(EditKind.javaScript)
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                            }

                            SettingsDivider(insetLeading: SettingsDesignTokens.sectionCardPaddingH)

                            Group {
                                switch editKind {
                                case .openURL:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("URL Template").font(.caption).foregroundStyle(.secondary)
                                        TextField("https://example.com/search?q={text}", text: $customURLTemplate)
                                            .textFieldStyle(.plain)
                                            .padding(8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color(white: 1.0, opacity: 0.08))
                                            )
                                    }
                                case .textSnippet:
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Snippet Template").font(.caption).foregroundStyle(.secondary)
                                        TextEditor(text: $customSnippetTemplate)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 90)
                                            .scrollContentBackground(.hidden)
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color(white: 1.0, opacity: 0.08))
                                            )
                                    }
                                case .shellScript:
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Shell Script (Zsh)").font(.caption).foregroundStyle(.secondary)
                                        TextEditor(text: $customShellScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 110)
                                            .scrollContentBackground(.hidden)
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color(white: 1.0, opacity: 0.08))
                                            )

                                        Toggle("Replace selected text with output", isOn: $replaceSelection)
                                            .font(.subheadline)
                                    }
                                case .javaScript:
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("JavaScript (JSC)").font(.caption).foregroundStyle(.secondary)
                                        TextEditor(text: $customJavaScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 120)
                                            .scrollContentBackground(.hidden)
                                            .padding(6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(Color(white: 1.0, opacity: 0.08))
                                            )

                                        Toggle("Replace selected text with output", isOn: $replaceSelection)
                                            .font(.subheadline)

                                        Toggle("Run asynchronously (enable promises & fetch)", isOn: $customJSIsAsync)
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
                            .padding(.bottom, SettingsDesignTokens.sectionCardPaddingV)
                        }
                    }
                } else if manifestMissing {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                            .padding(.top, 1)

                        Text("This action is a standalone script file with no editable manifest. Re-create it as an extension package to customize its behavior.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                }

                if !isCustomAction {
                    HStack {
                        Button(String(localized: "Reset to Default")) {
                            resetAppearance()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .disabled(manifestMissing)

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        // Form is centred at the shared measure; the scroll view stays full-width so the indicator sits at the edge.
        .settingsPaneWidth()
        .onAppear {
            loadInitialState()
            DispatchQueue.main.async {
                isLoaded = true
            }
        }
        .onDisappear {
            if isLoaded && !isDeleting {
                autoSave()
            }
            router.clearConfigurationRequest(for: action.id)
        }
        .task(id: customTitle) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .task(id: aliasText) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: aiProviderOverride) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .task(id: aiModelOverride) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .task(id: aiPrompt) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: displayMode) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: aiRequestsAdditionalInstruction) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: iconSymbol) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: deliveryPrefString) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: editKind) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: replaceSelection) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .onChange(of: customJSIsAsync) { _, _ in
            guard isLoaded, !isDeleting else { return }
            autoSave()
        }
        .task(id: customURLTemplate) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .task(id: customSnippetTemplate) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .task(id: customShellScript) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .task(id: customJavaScript) {
            guard isLoaded, !isDeleting else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !isDeleting else { return }
            autoSave()
        }
        .onReceive(router.pageCommands) { command in
            guard isCurrent else { return }
            switch command {
            case SettingsToolbarCommand.actionDuplicate: duplicate()
            case SettingsToolbarCommand.actionDelete: confirmDelete()
            default: break
            }
        }
        .alert(String(localized: "Uninstall \(customTitle.isEmpty ? action.title : customTitle)?"), isPresented: $showUninstallConfirmation) {
            Button(String(localized: "Uninstall"), role: .destructive) {
                if let packageID = extensionPackageID {
                    uninstallPackage(packageID)
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will remove the extension and all of its commands from OpenClip."))
        }
    }

    @ViewBuilder
    private var customNameField: some View {
        TextField(action.title, text: $customTitle, prompt: Text(action.title))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(white: 1.0, opacity: 0.08))
            )
            .frame(maxWidth: 220)
            .disabled(manifestMissing)
    }

    // MARK: - Extension Updates & Uninstall

    private func runCheckForUpdates(packageID: String) {
        updateCheckState = .checking
        Task {
            await updateManager.checkForUpdates()
            if updateManager.updatablePackageIDs.contains(packageID) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateCheckState = .idle
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    updateCheckState = .upToDate
                }
                try? await Task.sleep(for: .seconds(4))
                if updateCheckState == .upToDate {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        updateCheckState = .idle
                    }
                }
            }
        }
    }

    private func updateExtension(_ packageID: String) {
        isUpdating = true
        Task {
            defer { isUpdating = false }
            do {
                try await updateManager.update(packageID: packageID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
            } catch {
                router.notifyError(
                    title: String(localized: "Update Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func uninstallPackage(_ packageID: String) {
        let actionID = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions)?.uninstallActionID ?? packageID
        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: actionID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                router.pop()
            } catch {
                router.notifyError(
                    title: String(localized: "Uninstall Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Delete and duplicate

    /// Asks first, via the banner over the page.
    private func confirmDelete() {
        guard isCustomAction || isCustomAIPreset else { return }
        router.confirmDestructive(
            title: String(localized: "Delete?"),
            message: "",
            confirmTitle: String(localized: "Delete")
        ) {
            deleteAction()
        }
    }

    private func deleteAction() {
        isDeleting = true
        isLoaded = false
        let id = action.id
        KeyboardShortcuts.reset(.actionHotkey(id))
        if let preset = aiPreset {
            ActionBindingStore.shared.setAlias(nil, for: id)
            ActionCustomizationManager.shared.resetOverride(for: id)
            coordinator.setAIActionPlacement(actionIDs: [id], standalone: false)
            AIServiceManager.shared.presets.removeAll(where: { $0.id == preset.id })
            router.pop()
            return
        }
        ActionCoordinator.shared.deleteCustomAction(actionID: id)
        ActionCustomizationManager.shared.resetOverride(for: id)
        router.clearConfigurationRequest(for: id)
        router.pop()

        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: id)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
            } catch {
                let nsError = error as NSError
                if !(nsError.domain == "ExtensionManager" && nsError.code == 404) {
                    Log.extensions.error("Failed to remove custom action on disk '\(id, privacy: .public)': \(error.localizedDescription)")
                }
            }
        }
    }

    /// Makes a copy next to this action and opens the copy's page.
    private func duplicate() {
        isDuplicating = true
        Task {
            defer { isDuplicating = false }
            guard let newID = await ActionDuplicator.duplicate(actionID: action.id),
                  let copy = coordinator.actions.first(where: { $0.id == newID }) else { return }
            SettingsDestination.open(copy)
        }
    }

    // MARK: - Manifest lookup

    /// Finds the directory-backed manifest entry for the action; standalone scripts return nil (read-only).
    static func locateManifest(for action: any Action, in directory: URL = Constants.extensionsDirectory) -> LocatedManifest? {
        ExtensionManifestStore.locateManifest(for: action, in: directory)
    }

    /// True when the located entry is `actionID` itself; group members resolve to the parent group's index, so writing would rename the whole group.
    static func locatedEntryBacks(actionID: String, in state: LocatedManifest) -> Bool {
        guard state.manifest.actions.indices.contains(state.targetIndex) else { return false }
        let meta = state.manifest.actions[state.targetIndex]
        return ExtensionManager.uniformActionID(metadata: meta, manifest: state.manifest, index: state.targetIndex) == actionID
    }

    /// Resolves `ExtensionActionMetadata` for `actionID`, searching group `subActions` when needed.
    static func targetMetadata(for actionID: String, in state: LocatedManifest) -> ExtensionActionMetadata? {
        guard state.manifest.actions.indices.contains(state.targetIndex) else { return nil }
        let topMeta = state.manifest.actions[state.targetIndex]
        let topID = ExtensionManager.uniformActionID(metadata: topMeta, manifest: state.manifest, index: state.targetIndex)
        if topID == actionID {
            return topMeta
        }
        func searchSubActions(_ subActions: [ExtensionActionMetadata], parentID: String) -> ExtensionActionMetadata? {
            for (subIndex, sub) in subActions.enumerated() {
                let subID = "\(parentID).\(sub.id ?? String(subIndex))"
                if subID == actionID {
                    return sub
                }
                if let nested = sub.subActions, let found = searchSubActions(nested, parentID: subID) {
                    return found
                }
            }
            return nil
        }
        if let subActions = topMeta.subActions {
            return searchSubActions(subActions, parentID: topID)
        }
        return topMeta
    }

    static func scriptContent(for meta: ExtensionActionMetadata, in state: LocatedManifest) -> String? {
        if let code = meta.scriptCode, !code.isEmpty {
            return code
        }
        if let scriptName = meta.script, !scriptName.isEmpty {
            let fileURL = state.manifestURL.deletingLastPathComponent().appendingPathComponent(scriptName)
            return try? String(contentsOf: fileURL, encoding: .utf8)
        }
        return nil
    }

    static func jsProducesText(code: String) -> Bool {
        ScriptOutputSniffers.jsProducesText(code: code)
    }

    static func appleScriptProducesText(code: String) -> Bool {
        ScriptOutputSniffers.appleScriptProducesText(code: code)
    }

    static func shellProducesText(code: String) -> Bool {
        ScriptOutputSniffers.shellProducesText(code: code)
    }

    private static func unwrapBase(_ action: any Action) -> any Action {
        var cur = action
        while true {
            if let d = cur as? DeliveryDecoratedAction { cur = d.base; continue }
            if let k = cur as? KeywordDecoratedAction { cur = k.base; continue }
            if let m = cur as? MenuDecoratedAction { cur = m.base; continue }
            if let rich = cur as? RichInputAction { cur = rich.base; continue }
            break
        }
        return cur
    }

    // MARK: - State loading

    /// Only GUI-authored custom actions (com.custom.<id>) allow logic editing; other packages stay read-only.
    static func isLogicEditable(manifestIdentifier: String) -> Bool {
        manifestIdentifier.hasPrefix(Constants.customIdentifierPrefix)
    }

    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)

        aliasText = ActionBindingStore.shared.alias(for: action.id) ?? ""
        customTitle = override?.customTitle ?? action.title
        if let pref = override?.deliveryPreference {
            deliveryPrefString = pref.rawValue
        } else {
            deliveryPrefString = Self.defaultDeliveryPrefString(for: action)
        }
        // A saved "star" on an AI preset is a deliberate icon choice, not the legacy placeholder.
        initialStoredSymbol = isAIPreset
            ? override?.customIconSymbol
            : Self.sanitizedStoredSymbol(override?.customIconSymbol, actionIcon: action.icon)
        // Preview the icon that returns when switching back to Show Icon; a Show Text override must not replace it.
        seedBaseline(from: ActionCustomizationManager.shared.tableIcon(for: action))
        displayMode = Self.initialDisplayMode(override: override, actionIcon: action.icon)
        if let customAction = action as? CustomAction {
            manifestState = nil
            logicEditable = true
            manifestMissing = false
            loadCustomType(from: customAction)
            return
        }

        if isBuiltin || isAIPreset {
            manifestState = nil
            logicEditable = false
            manifestMissing = false
            aiPrompt = aiPreset?.prompt ?? ""
            aiProviderOverride = aiPreset?.provider
            aiModelOverride = aiPreset?.model
            aiRequestsAdditionalInstruction = aiPreset?.requestsAdditionalInstruction ?? false
            return
        }

        manifestState = Self.locateManifest(for: action)
        guard let state = manifestState else {
            // Standalone script: the JSON manifest is the only editable surface, so stay read-only.
            logicEditable = false
            manifestMissing = true
            return
        }
        manifestMissing = false

        // Only com.custom.<id> packages keep logic editing; store and developer packages stay read-only.
        guard Self.isLogicEditable(manifestIdentifier: state.manifest.identifier) else {
            logicEditable = false
            return
        }
        let meta = state.manifest.actions[state.targetIndex]
        switch meta.kind {
        case .url, .webSearch:
            customURLTemplate = meta.url ?? ""
            editKind = .openURL
            logicEditable = true
        case .textSnippet:
            customSnippetTemplate = meta.scriptCode ?? ""
            editKind = .textSnippet
            logicEditable = true
        case .shellInline:
            customShellScript = meta.scriptCode ?? ""
            editKind = .shellScript
            logicEditable = true
        case .js:
            customJavaScript = meta.scriptCode ?? ""
            customJSIsAsync = meta.isAsync ?? false
            editKind = .javaScript
            logicEditable = true
        default:
            logicEditable = false
        }
    }

    /// Symbol icons become the editable baseline; file, remote and text-glyph icons stay out of the string field and preview via `baseIconState`.
    private func seedBaseline(from icon: ActionIcon) {
        if case .symbol(let sym) = icon {
            iconSymbol = sym
            baseIconState = nil
        } else if case .local(let url) = icon, url.path.hasPrefix(Constants.customIconsDirectory.path) {
            iconSymbol = "\(Constants.customIconPrefix)\(url.lastPathComponent)"
            baseIconState = nil
        } else {
            iconSymbol = ""
            baseIconState = icon
        }
        initialIconSymbol = iconSymbol
    }

    private func loadCustomType(from customAction: CustomAction) {
        switch customAction.type {
        case .openURL(let url):
            editKind = .openURL
            customURLTemplate = url
        case .textSnippet(let snippet):
            editKind = .textSnippet
            customSnippetTemplate = snippet
        case .shellScript(let script, let replace):
            editKind = .shellScript
            customShellScript = script
            replaceSelection = replace
        case .javaScript(let script, let isAsync, let replace):
            editKind = .javaScript
            customJavaScript = script
            customJSIsAsync = isAsync
            replaceSelection = replace
        }
    }

    private func resetAppearance() {
        ActionCustomizationManager.shared.resetOverride(for: action.id)
        appearanceResetPending = false
        initialStoredSymbol = nil
        deliveryPrefString = Self.defaultDeliveryPrefString(for: action)
        seedBaseline(from: action.icon)
        if case .text = action.icon {
            displayMode = 1
        } else {
            displayMode = 0
        }
        customTitle = action.title
        aliasText = ""
        _ = ActionBindingStore.shared.setAlias("", for: action.id)
        aliasError = nil
        if let customAction = action as? CustomAction {
            _ = saveCustomActionChanges(customAction)
        } else if !isBuiltin && !isAIPreset && logicEditable {
            Task {
                _ = await saveManifestChanges()
            }
        }
    }

    // MARK: - Saving

    private func fail(_ message: String) -> Bool {
        withAnimation(.easeInOut(duration: 0.18)) {
            saveErrorMessage = message
        }
        return false
    }

    private func saveAlias() {
        guard ActionIdentity.isBindable(action) else { return }
        switch ActionBindingStore.shared.setAlias(aliasText, for: action.id) {
        case .accepted, .cleared:
            aliasError = nil
        case .invalid:
            aliasError = String(localized: "Letters, numbers, and hyphens only")
        case .collision:
            aliasError = String(localized: "Alias already in use")
        }
    }

    private func autoSave() {
        guard isLoaded, !isDeleting, !manifestMissing else { return }
        guard coordinator.actions.contains(where: { $0.id == action.id }) else { return }
        saveAlias()
        if appearanceResetPending {
            ActionCustomizationManager.shared.resetOverride(for: action.id)
            appearanceResetPending = false
        } else {
            saveAppearanceOverride()
        }
        if let customAction = action as? CustomAction {
            _ = saveCustomActionChanges(customAction)
            return
        }
        if isAIPreset {
            guard var preset = aiPreset else { return }
            let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = aiModelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedModel = model?.isEmpty == true ? nil : model
            var changed = false
            if !prompt.isEmpty, prompt != preset.prompt {
                preset.prompt = prompt
                changed = true
            }
            if preset.provider != aiProviderOverride || preset.model != resolvedModel {
                preset.provider = aiProviderOverride
                preset.model = resolvedModel
                changed = true
            }
            if aiRequestsAdditionalInstruction != preset.requestsAdditionalInstruction {
                preset.requestsAdditionalInstruction = aiRequestsAdditionalInstruction
                changed = true
            }
            if changed {
                AIServiceManager.shared.updatePreset(preset)
            }
            return
        }
        if !isBuiltin && logicEditable {
            Task {
                _ = await saveManifestChanges()
            }
        }
    }

    private func saveCustomActionChanges(_ customAction: CustomAction) -> Bool {
        let finalTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = finalTitle.isEmpty ? customAction.title : finalTitle
        let finalIcon = (iconSymbol != initialIconSymbol && !iconSymbol.isEmpty) ? iconSymbol : customAction.iconName

        let newType: CustomActionType
        switch editKind {
        case .openURL:
            newType = .openURL(urlTemplate: customURLTemplate)
        case .textSnippet:
            newType = .textSnippet(template: customSnippetTemplate)
        case .shellScript:
            newType = .shellScript(script: customShellScript, replaceSelection: replaceSelection)
        case .javaScript:
            newType = .javaScript(script: customJavaScript, isAsync: customJSIsAsync, replaceSelection: replaceSelection)
        }

        let updated = CustomAction(
            id: customAction.id,
            title: resolvedTitle,
            iconName: finalIcon,
            type: newType,
            chrome: customAction.chrome,
            rules: customAction.rules
        )

        ActionCoordinator.shared.saveCustomAction(updated)
        return true
    }

    private func saveAppearanceOverride() {
        let titleOverride: String? = (customTitle.isEmpty || customTitle == action.title) ? nil : customTitle
        let symbolOverride = Self.resolvedIconModeSymbolOverride(
            displayMode: displayMode,
            current: iconSymbol,
            initial: initialIconSymbol,
            stored: initialStoredSymbol,
            action: action
        )
        let textOverride: String? = (displayMode == 1) ? (customTitle.isEmpty ? action.title : customTitle) : nil

        ActionCustomizationManager.shared.setOverride(
            for: action.id,
            title: titleOverride,
            symbol: symbolOverride,
            text: textOverride
        )

        let defaultPref = Self.defaultDeliveryPrefString(for: action)
        let pref: ResultDeliveryPreference? = (deliveryPrefString == defaultPref)
            ? nil
            : ResultDeliveryPreference(rawValue: deliveryPrefString)
        ActionCustomizationManager.shared.setDeliveryPreference(pref, for: action.id)
    }

    /// A stored symbol keeps Show Icon, even for text-glyph builtins; a text override otherwise opens Show Text.
    static func initialDisplayMode(override: ActionOverride?, actionIcon: ActionIcon) -> Int {
        if override?.customIconText != nil { return 1 }
        if override?.customIconSymbol != nil { return 0 }
        if case .text = actionIcon { return 1 }
        return 0
    }

    /// Symbol Show Icon resolves to for text-glyph builtins and AI presets, before any replacement is picked.
    static func iconModeFallbackSymbol(for action: any Action) -> String? {
        guard case .text = action.icon,
              ActionIdentity.isBuiltin(action) || ActionIdentity.isAIPreset(action) else { return nil }
        return (action as? any ConfigurableAction)?.preferenceIconName
    }

    // MARK: - Appearance save decisions (pure, unit-tested)

    /// Symbol to persist for the icon field: a user-picked change wins; an untouched field keeps the stored value.
    static func resolvedSymbolOverride(current: String, initial: String, stored: String?) -> String? {
        guard current.isEmpty || current == initial else { return current }
        return stored
    }

    /// Symbol to persist for the display mode. Show Icon needs a resolvable symbol, so text-glyph builtins persist their preference symbol.
    static func resolvedIconModeSymbolOverride(
        displayMode: Int,
        current: String,
        initial: String,
        stored: String?,
        action: any Action
    ) -> String? {
        let fromField = resolvedSymbolOverride(current: current, initial: initial, stored: stored)
        if let fromField { return fromField }
        guard displayMode == 0 else { return nil }
        return iconModeFallbackSymbol(for: action)
    }

    /// Legacy "star" placeholders are treated as absent so the next Save heals them, unless the action's own icon is "star".
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
        guard logicEditable else { return true }
        guard let state = manifestState else {
            // Save is disabled in this state; if reached anyway, surface the reason rather than drop edits silently.
            return fail(String(localized: "This action is backed by a standalone script file with no editable manifest, so changes cannot be saved here."))
        }

        // Group sub-actions save as they are edited; writing the group entry here would rename the parent group.
        guard Self.locatedEntryBacks(actionID: action.id, in: state) else { return true }

        let meta = state.manifest.actions[state.targetIndex]
        let finalTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only rewrite the icon when changed, so local-file icons on extension actions aren't clobbered.
        let finalIcon = (iconSymbol != initialIconSymbol && !iconSymbol.isEmpty) ? iconSymbol : meta.icon

        var newURL = meta.url
        var newType = meta.type
        var newScriptCode = meta.scriptCode
        if logicEditable {
            switch editKind {
            case .openURL:
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
            case .javaScript:
                newURL = nil
                newType = "javascript"
                newScriptCode = customJavaScript
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
            isAsync: editKind == .javaScript ? customJSIsAsync : meta.isAsync,
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
            inline: meta.inline,
            localizedTitle: (finalTitle.isEmpty || finalTitle == meta.title || finalTitle == meta.localizedTitle?.resolve()) ? meta.localizedTitle : nil,
            localizedLoadingMessage: meta.localizedLoadingMessage,
            output: meta.output,
            result: meta.result,
            captureRtf: meta.captureRtf,
            captureHtml: meta.captureHtml
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
            localizedDescription: state.manifest.localizedDescription,
            author: state.manifest.author,
            output: state.manifest.output,
            result: state.manifest.result
        )

        do {
            try ExtensionManifestStore.writeManifest(updatedManifest, to: state.manifestURL)
        } catch {
            Log.factory.error("Failed to save action manifest: \(error.localizedDescription)")
            return fail(String(localized: "Failed to save the action manifest: \(error.localizedDescription)"))
        }

        // Re-trust with the new fingerprint, but only if already trusted: an edit save is not consent.
        await ExtensionManager.shared.retrustAfterAuthorizedEdit(packageID: state.manifest.identifier)
        return true
    }
}
