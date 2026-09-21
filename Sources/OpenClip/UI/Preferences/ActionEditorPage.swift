// ActionEditorPage.swift
// OpenClip
//
// One action's settings as a page of the Settings window: appearance (name, icon, how the popup
// bar shows it), keyboard (alias, hotkey), and either the options the action declares or, for a
// GUI-authored custom action, its execution logic. Whether it is on, and duplicating or deleting
// it, are in the toolbar beside the back and forward arrows — they belong to the action, not to
// this form, and they take effect without a Save. A built-in action shows it
// as its own sidebar page; an extension's command, a custom action or a group reach it from their
// owner's page, the Customize list or the Shortcuts table.
//
// This used to be an `.applicationDefined` NSPopover pinned to a list row: a 370pt floating panel
// that ignored clicks in the list behind it, ignored Escape, and stayed up when you changed panes.
// As a page it gets the window's width, the toolbar's title says which action it is, and the way
// back is the same arrow as everywhere else.
import SwiftUI
import AppKit
import Core
import KeyboardShortcuts

@MainActor
public struct ActionEditorPage: View {
    let action: any Action
    /// True when the page is a sidebar row of its own (a built-in action): there is nothing to go
    /// back to, so Cancel becomes Revert and Save stays on the page.
    let isSidebarPage: Bool
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @Setting(SettingKey.disabledActionIDs) private var disabledActionIDs: Set<String>
    @Setting(SettingKey.disabledPackages) private var disabledPackages: Set<String>

    @State private var customTitle: String = ""
    @State private var iconSymbol: String = ""
    @State private var initialIconSymbol: String = ""
    /// Icon-symbol customization stored before the page opened (nil = none). An untouched icon
    /// field round-trips this on Save instead of writing the picker's baseline, so title-only
    /// edits can't clobber package-file / remote-image / text-glyph icons.
    @State private var initialStoredSymbol: String? = nil
    /// The action's effective real icon while no replacement has been picked from the picker;
    /// drives the honest preview in the Appearance fields.
    @State private var baseIconState: ActionIcon? = nil
    /// Set by Reset to Default; the persisted override is cleared on Save (not immediately), so
    /// Cancel still backs out of an accidental reset.
    @State private var appearanceResetPending = false
    @State private var displayMode: Int = 0 // 0 = Icon, 1 = Text
    @State private var isIconHovered = false
    @State private var isIconPickerPresented = false

    // Custom Action State. The Type picker selects a plain kind — the payload values live in the
    // field state below — so the segment highlight stays stable while the user edits text (a
    // CustomActionType selection would embed the live string and unhighlight on every keystroke).
    private enum EditKind: Hashable {
        case openURL
        case textSnippet
        case shellScript

        static let webSearch: EditKind = .openURL
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
    // page must stay read-only instead of dropping edits on Save.
    @State private var manifestMissing: Bool = false
    /// Why the last Save did not go through. Shown inline above the buttons, where an alert used
    /// to run modal over the window.
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
    @State private var isHoveringUpdate = false
    @State private var isHoveringUninstall = false

    private enum UpdateCheckState: Equatable {
        case idle
        case checking
        case upToDate
    }

    public init(
        action: any Action,
        isSidebarPage: Bool = false
    ) {
        self.action = action
        self.isSidebarPage = isSidebarPage
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

    private var canDuplicate: Bool {
        ActionIdentity.canDuplicate(action)
    }

    /// True when this level of the stack is the one on screen.
    private var isCurrent: Bool {
        switch router.currentPage {
        case .action(let id), .builtinAction(let id): return id == action.id
        case .extensionPackage(let id):
            return ActionIdentity.extensionPackageID(of: action) == id
        default: return false
        }
    }

    private var isBuiltin: Bool {
        ActionIdentity.isBuiltin(action)
    }

    /// The request that opened this page from outside the window, if any: the popup found the
    /// action with required options unset.
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

    /// Banner text when the page was opened because the action needs configuration. Falls back to a
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

    /// The hero tile uses the action or extension's meaningful semantic color.
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
        if action.chrome.outputKind == .text || action.chrome.outputKind == .dynamic {
            return true
        }
        if action.chrome.outputKind == .none || action.chrome.outputKind == .file {
            return false
        }
        if isBuiltin { return false }
        if ActionIdentity.isAIPreset(action) || action.chrome.launchesAI { return true }
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

    private var actionDescription: String {
        let state = manifestState ?? Self.locateManifest(for: action)
        if let desc = state?.manifest.localizedDescription?.resolve() ?? state?.manifest.description,
           !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return desc
        }
        switch action.id {
        case "builtin.calculate":
            return String(localized: "Evaluate math expressions.")
        case "builtin.define":
            return String(localized: "Look a word up in the macOS Dictionary.")
        case "builtin.search":
            return String(localized: "Search the web with your chosen engine.")
        case "builtin.copy":
            return String(localized: "Copy the selected text.")
        case "builtin.paste":
            return String(localized: "Paste the clipboard content.")
        case "builtin.cut":
            return String(localized: "Cut the selected text.")
        case "builtin.calendar":
            return String(localized: "Add the selected text as a calendar event.")
        case "builtin.openurl":
            return String(localized: "Open the selected text as a link.")
        case "builtin.reveal_in_finder":
            return String(localized: "Reveal the selected file path in Finder.")
        case "builtin.completion":
            return String(localized: "Complete the word you are typing.")
        default:
            break
        }
        if ActionIdentity.isAIPreset(action) || action.chrome.launchesAI {
            return String(localized: "Run the selected text through AI.")
        }
        if isCustomAction {
            return String(localized: "A custom action you wrote.")
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           let info = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions) {
            return info.name
        }
        return ""
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        } else if updateManager.updatablePackageIDs.contains(packageID) {
            Button {
                updateExtension(packageID)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(String(localized: "Update"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.green.opacity(0.12))
            )
            .transition(.opacity)
        } else {
            Button {
                runCheckForUpdates(packageID: packageID)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(String(localized: "Check for Updates"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(isHoveringUpdate ? SettingsDesignTokens.primaryText : SettingsDesignTokens.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHoveringUpdate ? 0.10 : 0.06))
                )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringUpdate = $0 }
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
                            Text(displayTitle.isEmpty ? action.title : displayTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SettingsDesignTokens.primaryText)
                                .lineLimit(1)

                            if let version = manifestVersion, !version.isEmpty {
                                Text("v\(version)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(white: 1.0, opacity: 0.08)))
                            }
                        }

                        if !actionDescription.isEmpty {
                            Text(actionDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsDesignTokens.secondaryText)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
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

                            Button {
                                showUninstallConfirmation = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10.5))
                                    Text(String(localized: "Uninstall"))
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundStyle(isHoveringUninstall ? Color.red : Color.red.opacity(0.85))
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isHoveringUninstall ? Color.red.opacity(0.15) : Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isHoveringUninstall = $0 }
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
                        systemImage: "app.dashed"
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
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(white: 1.0, opacity: 0.08))
                            )
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
                        systemImage: "textformat"
                    ) {
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

                    SettingsDivider()

                    SettingsRow(
                        title: "Show as",
                        subtitle: "Display as an icon or as text in the popup bar.",
                        systemImage: "rectangle.split.2x1"
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
                                systemImage: "keyboard"
                            ) {
                                Shortcut(for: .actionHotkey(action.id))
                            }

                            SettingsDivider()

                            SettingsRow(
                                title: "Search Alias",
                                subtitle: "Keyword to jump to this action in the search palette.",
                                systemImage: "magnifyingglass"
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
                                systemImage: "arrow.turn.down.right"
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

                if isCustomAction {
                    SettingsCard {
                        Button(role: .destructive) {
                            confirmDelete()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Action…")
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        // Centre the form at the shared measure while its scroll view runs the full width of the
        // detail column, so the scroll indicator stays at the window edge.
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
        .onChange(of: displayMode) { _, _ in
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

    /// Asks first, in the banner that floats over the page, the way every destructive step in this
    /// window does.
    private func confirmDelete() {
        guard isCustomAction else { return }
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

    /// Locates the manifest package whose identifier matches the action's chrome source (or, as a
    /// fallback for stray `.custom` actions, its id) and returns the target action's edit state.
    /// Only directory-backed manifest packages are considered; a standalone script file with the
    /// same identifier returns nil, which the page treats as a read-only, uneditable action.
    static func locateManifest(for action: any Action, in directory: URL = Constants.extensionsDirectory) -> LocatedManifest? {
        ExtensionManifestStore.locateManifest(for: action, in: directory)
    }

    /// True when the located manifest entry is `actionID` itself. The locator resolves a nested
    /// sub-action to its parent group's top-level index, so for a group member this is false and
    /// the page must not write the entry — doing so would stamp the member's title and icon onto
    /// the whole group. Pure, unit-tested.
    static func locatedEntryBacks(actionID: String, in state: LocatedManifest) -> Bool {
        guard state.manifest.actions.indices.contains(state.targetIndex) else { return false }
        let meta = state.manifest.actions[state.targetIndex]
        return ExtensionManager.uniformActionID(metadata: meta, manifest: state.manifest, index: state.targetIndex) == actionID
    }

    /// Resolves the specific `ExtensionActionMetadata` for `actionID`. If `actionID` belongs to a
    /// sub-action of a group, searches through the group's `subActions` hierarchy.
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

    /// Determines if a JavaScript extension produces text output governed by the delivery preference.
    static func jsProducesText(code: String) -> Bool {
        ScriptOutputSniffers.jsProducesText(code: code)
    }

    /// Determines if an AppleScript extension produces text output.
    static func appleScriptProducesText(code: String) -> Bool {
        ScriptOutputSniffers.appleScriptProducesText(code: code)
    }

    /// Determines if a shell extension produces text output to stdout.
    static func shellProducesText(code: String) -> Bool {
        ScriptOutputSniffers.shellProducesText(code: code)
    }

    private static func unwrapBase(_ action: any Action) -> any Action {
        var cur = action
        while true {
            if let d = cur as? DeliveryDecoratedAction { cur = d.base; continue }
            if let k = cur as? KeywordDecoratedAction { cur = k.base; continue }
            if let m = cur as? MenuDecoratedAction { cur = m.base; continue }
            break
        }
        return cur
    }

    // MARK: - State loading

    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)

        aliasText = ActionBindingStore.shared.alias(for: action.id) ?? ""
        customTitle = override?.customTitle ?? action.title
        if let pref = override?.deliveryPreference {
            deliveryPrefString = pref.rawValue
        } else {
            deliveryPrefString = Self.defaultDeliveryPrefString(for: action)
        }
        initialStoredSymbol = Self.sanitizedStoredSymbol(override?.customIconSymbol, actionIcon: action.icon)
        seedBaseline(from: ActionCustomizationManager.shared.popupIcon(for: action))
        displayMode = Self.initialDisplayMode(override: override, actionIcon: action.icon)
        if let customAction = action as? CustomAction {
            manifestState = nil
            logicEditable = true
            manifestMissing = false
            loadCustomType(from: customAction)
            return
        }

        if isBuiltin {
            manifestState = nil
            logicEditable = false
            manifestMissing = false
            return
        }

        manifestState = Self.locateManifest(for: action)
        guard let state = manifestState else {
            // Standalone-script action (or a stray non-builtin with no manifest on disk): the JSON
            // manifest is the only editable surface, so there is nothing to write. Keep the page
            // read-only and disable Save rather than silently dropping edits.
            logicEditable = false
            manifestMissing = true
            return
        }
        manifestMissing = false

        // Raw execution-logic editing (type/URL/script) is a GUI-authored-action surface only:
        // com.custom.<id> packages keep the editor, while store and developer extension packages
        // stay read-only — their behavior belongs to the package, and an accidental rewrite here
        // would silently mutate an installed third-party extension.
        guard state.manifest.identifier.hasPrefix(Constants.customIdentifierPrefix) else {
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
        } else if !isBuiltin {
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
        if !isBuiltin {
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

    /// The display mode the editor opens in. Show Text wins when a text override is stored (it
    /// outranks a symbol in `popupIcon`); a stored symbol override means the user already switched
    /// to Show Icon, which must stick even for builtins whose own icon is a text glyph (Copy/Cut/
    /// Paste) — those otherwise reopen as Show Text and make the saved switch look lost.
    static func initialDisplayMode(override: ActionOverride?, actionIcon: ActionIcon) -> Int {
        if override?.customIconText != nil { return 1 }
        if override?.customIconSymbol != nil { return 0 }
        if case .text = actionIcon { return 1 }
        return 0
    }

    /// The symbol Show Icon mode resolves to for builtin actions whose own icon is a text glyph
    /// (Copy/Cut/Paste), driving the honest icon-mode preview before any replacement is picked.
    static func iconModeFallbackSymbol(for action: any Action) -> String? {
        guard case .text = action.icon, ActionIdentity.isBuiltin(action) else { return nil }
        return (action as? any ConfigurableAction)?.preferenceIconName
    }

    // MARK: - Appearance save decisions (pure, unit-tested)

    /// Symbol value to persist for the icon field. A genuinely user-picked change wins; an untouched
    /// field round-trips whatever was stored before (nil when there was none), so editing only the
    /// title never rewrites the icon.
    static func resolvedSymbolOverride(current: String, initial: String, stored: String?) -> String? {
        guard current.isEmpty || current == initial else { return current }
        return stored
    }

    /// Symbol override to persist for the chosen display mode. Show Icon mode needs a resolvable
    /// symbol: for builtin actions whose own icon is a text glyph (Copy/Cut/Paste) the builtin's
    /// preference symbol is persisted — otherwise `ActionCustomizationManager.popupIcon` keeps
    /// resolving the text glyph and the switch to icon mode never takes effect. A field-level pick
    /// or a previously stored symbol wins. Show Text mode only round-trips the icon field.
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
            return fail(String(localized: "This action is backed by a standalone script file with no editable manifest, so changes cannot be saved here."))
        }

        // A sub-action of an extension group resolves to the group's manifest entry. Its
        // appearance override was persisted above and its option values save as they are edited,
        // so there is nothing left to write — and writing here would rename the parent group.
        guard Self.locatedEntryBacks(actionID: action.id, in: state) else { return true }

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
            inline: meta.inline,
            localizedTitle: (finalTitle.isEmpty || finalTitle == meta.title || finalTitle == meta.localizedTitle?.resolve()) ? meta.localizedTitle : nil,
            localizedLoadingMessage: meta.localizedLoadingMessage,
            output: meta.output,
            result: meta.result
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

        // Re-trust the package with its newly computed fingerprint so tamper detection does not
        // falsely flag authorized preferences edits — but only if it was already trusted: a
        // revoked or never-enabled package keeps its trust state (an edit save is not consent).
        await ExtensionManager.shared.retrustAfterAuthorizedEdit(packageID: state.manifest.identifier)
        return true
    }
}
