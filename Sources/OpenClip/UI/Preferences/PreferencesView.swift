// PreferencesView.swift
// OpenClip
//
// The Settings window: Liquid Glass layout with a fixed-width sidebar on the window background and an inset rounded detail card.

import SwiftUI
import Combine
import Core
import KeyboardShortcuts

/// Opens the window on a page; maps onto the router's sidebar pages.
public enum PreferenceTab: String, CaseIterable, Hashable, Sendable {
    case general = "General"
    case customize = "Customize"
    case appearance = "Appearance"
    case actions = "Actions"
    case shortcuts = "Shortcuts"
    case ai = "AI"
    case store = "Store"
    case appRules = "App Rules"
    case about = "About"

    public var localizedTitle: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    public var windowTitle: String {
        page.staticTitle ?? String(localized: String.LocalizationValue(rawValue))
    }

    public var page: SettingsPage {
        switch self {
        case .general: return .general
        case .customize, .appearance: return .appearance
        case .actions, .shortcuts: return .customize
        case .ai: return .ai
        case .store: return .store
        case .appRules: return .appRules
        case .about: return .about
        }
    }
}

@MainActor
public struct PreferencesView: View {
    private static let customizeListMaxWidth: CGFloat = SettingsLayout.contentMaxWidth

    @Setting(SettingKey.disabledActionIDs) private var disabledActionIDs
    @Setting(SettingKey.disabledPackages) private var disabledPackages
    /// Lets the toolbar's New Group seed a group with the selection.
    @State private var selectedRowIDs: Set<String> = []
    @State private var customizeQuery = ""
    @State private var packageDetails: ExtensionPackageDetails?
    @State private var packageReloadToken = 0
    @State private var systemColorsToken = 0
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var aiManager = AIServiceManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var toolbarModel: PreferencesToolbarModel

    private let initialPage: SettingsPage
    @State private var didApplyInitialPage = false

    public init(
        initialTab: PreferenceTab = .general,
        toolbarModel: PreferencesToolbarModel = PreferencesToolbarModel()
    ) {
        initialPage = initialTab.page
        _toolbarModel = ObservedObject(wrappedValue: toolbarModel)
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: SettingsDesignTokens.sidebarWidth)

            detail
        }
        .frame(minWidth: 760, minHeight: 560)
        .background {
            ZStack {
                VisualEffectView(
                    material: .sidebar,
                    blendingMode: .behindWindow,
                    state: .active
                )
                SettingsDesignTokens.windowScrim
            }
        }
        .transparentScrollBackground()
        .ignoresSafeArea()
        .onAppear {
            if !didApplyInitialPage {
                didApplyInitialPage = true
                router.select(initialPage)
            }
            syncToolbar()
            Task {
                await storeViewModel.loadAll(limit: Constants.storeFullCatalogLimit)
                await ExtensionUpdateManager.shared.checkForUpdates()
            }
        }
        .task(id: packageDetailsKey) {
            await loadPackageDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipExtensionsDidChange)) { _ in
            packageReloadToken += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            systemColorsToken += 1
        }
        .onChange(of: router.path) { _, newPath in
            syncToolbar()
            if newPath.last == .store && storeViewModel.extensions.isEmpty {
                Task {
                    await storeViewModel.loadAll(limit: Constants.storeFullCatalogLimit)
                }
            }
        }
        .onReceive(coordinator.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        .onReceive(customizationManager.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        .onReceive(aiManager.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        .onReceive(toolbarModel.actions) { action in
            switch action {
            case .newGroup:
                router.push(.newGroup(
                    memberIDs: CustomizePage.groupCandidates(selectedRowIDs: selectedRowIDs, coordinator: coordinator)
                ))
            case .addCustomAction: router.push(.newCustomAction())
            case .openCustomActions: router.select(.customActions)
            case .addApplication: router.push(.addApplication)
            case .addAIAction: router.push(.aiNewPreset)
            case .installExtensionFile: presentInstallExtensionPanel()
            case .refreshStore: Task { await storeViewModel.refreshCatalog() }
            case .setStoreSort(let sort): storeViewModel.selectedSort = sort
            case .setPageToggle(let isOn): setPageToggle(isOn)
            case .pageMenuItem(let id): runPageMenuItem(id)
            }
        }
        .onChange(of: toolbarModel.searchQuery) { _, query in
            switch toolbarModel.page {
            case .store:
                guard storeViewModel.searchQuery != query else { return }
                storeViewModel.searchQuery = query
                storeViewModel.queryDidChange()
            case .customize, .shortcuts:
                if customizeQuery != query { customizeQuery = query }
            default:
                break
            }
        }
        .onChange(of: storeViewModel.searchQuery) { _, query in
            guard toolbarModel.page == .store else { return }
            if toolbarModel.searchQuery != query {
                toolbarModel.searchQuery = query
            }
            storeViewModel.queryDidChange()
        }
        .onChange(of: customizeQuery) { _, query in
            guard toolbarModel.page == .customize || toolbarModel.page == .shortcuts else { return }
            // Filtered-out rows must not stay in a new group's selection.
            selectedRowIDs.removeAll()
            toolbarModel.searchQuery = query
        }
        .onChange(of: storeViewModel.selectedSort) { _, sort in
            guard toolbarModel.storeSort != sort else { return }
            toolbarModel.storeSort = sort
        }
        .onChange(of: storeViewModel.isLoading) { _, isLoading in
            toolbarModel.isRefreshing = isLoading
            syncToolbar()
        }
        .onChange(of: disabledActionIDs) { _, _ in
            syncToolbar()
        }
        .onChange(of: disabledPackages) { _, _ in
            syncToolbar()
        }
        .onChange(of: packageDetails) { _, _ in syncToolbar() }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenActionConfiguration)) { notification in
            guard let request = notification.userInfo?["request"] as? ConfigurationRequest,
                  let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            router.openConfiguration(for: action, request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipSelectPreferencesTab)) { notification in
            if let tab = notification.object as? PreferenceTab {
                router.select(tab.page)
            }
        }
    }

    // MARK: - Toolbar Sync

    private func syncToolbar() {
        toolbarModel.page = router.currentPage
        toolbarModel.title = title(for: router.currentPage)
        toolbarModel.pageToggle = pageToggle(for: router.currentPage)
        toolbarModel.pageMenuItems = pageMenuItems(for: router.currentPage)
        toolbarModel.searchQuery = searchQuery(for: router.currentPage)
    }

    private func searchQuery(for page: SettingsPage) -> String {
        switch page {
        case .store: return storeViewModel.searchQuery
        case .customize, .shortcuts: return customizeQuery
        default: return ""
        }
    }

    private func subjectAction(of page: SettingsPage) -> (any Action)? {
        switch page {
        case .action(let id), .builtinAction(let id):
            return coordinator.actions.first(where: { $0.id == id })
        default:
            return nil
        }
    }

    private func pageToggle(for page: SettingsPage) -> SettingsToolbarToggle? {
        switch page {
        case .ai:
            return nil
        case .extensionPackage(let id):
            guard let info = InstalledExtensionInfo.info(for: id, in: coordinator.actions) else { return nil }
            if info.commands.count == 1 && !info.isGroup {
                return nil
            }
            let isAllCommandsDisabled = !info.commands.isEmpty && info.commands.allSatisfy { disabledActionIDs.contains($0.id) }
            let isEnabled = info.gatedReason == nil && !disabledPackages.contains(id) && !isAllCommandsDisabled
            return SettingsToolbarToggle(
                isOn: isEnabled,
                label: String(localized: "Enable \(info.name)")
            )
        default:
            return nil
        }
    }

    private func setPageToggle(_ isOn: Bool) {
        switch router.currentPage {
        case .ai:
            aiManager.isAIEnabled = isOn
        case .extensionPackage(let id):
            guard let info = InstalledExtensionInfo.info(for: id, in: coordinator.actions) else { return }
            ActionEnablement.packageBinding(
                packageID: id,
                gatedReason: info.gatedReason,
                disabledPackages: $disabledPackages,
                disabledActionIDs: $disabledActionIDs
            ).wrappedValue = isOn
        default:
            guard let action = subjectAction(of: router.currentPage) else { return }
            ActionEnablement.binding(
                for: action,
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages
            ).wrappedValue = isOn
        }
        syncToolbar()
    }

    private func pageMenuItems(for page: SettingsPage) -> [SettingsToolbarMenuItem] {
        switch page {
        case .store:
            return []
        case .extensionPackage(let id):
            guard InstalledExtensionInfo.info(for: id, in: coordinator.actions) != nil else { return [] }
            let details = packageDetails?.packageID == id ? packageDetails : nil
            return SettingsToolbarAccessories.extensionMenuItems(
                .init(hasReadme: details?.readmeURL != nil, hasFolder: details?.directoryURL != nil)
            )
        default:
            guard let action = subjectAction(of: page) else { return [] }
            let isExt = ActionIdentity.extensionPackageID(of: action) != nil
            return SettingsToolbarAccessories.actionMenuItems(
                .init(
                    canDuplicate: ActionIdentity.canDuplicate(action),
                    canDelete: SettingsDestination.isCustomAction(action),
                    canUninstall: isExt
                )
            )
        }
    }

    private func runPageMenuItem(_ id: String) {
        switch id {
        case SettingsToolbarCommand.storeInstallFile:
            presentInstallExtensionPanel()
        case SettingsToolbarCommand.storeRefresh:
            Task { await storeViewModel.refreshCatalog() }
        case SettingsToolbarCommand.extensionReadme:
            if let url = packageDetails?.readmeURL {
                NSWorkspace.shared.open(url)
            }
        case SettingsToolbarCommand.extensionFinder:
            if let url = packageDetails?.directoryURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case SettingsToolbarCommand.extensionUninstall:
            confirmUninstall()
        default:
            router.pageCommands.send(id)
        }
    }

    private func confirmUninstall() {
        let packageID: String?
        if case .extensionPackage(let id) = router.currentPage {
            packageID = id
        } else if let action = subjectAction(of: router.currentPage) {
            packageID = ActionIdentity.extensionPackageID(of: action)
        } else {
            packageID = nil
        }
        guard let packageID,
              let info = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions) else { return }
        router.confirmDestructive(
            title: String(localized: "Uninstall \(info.name)?"),
            message: "",
            confirmTitle: String(localized: "Uninstall")
        ) {
            uninstallExtension(info)
        }
    }

    private func uninstallExtension(_ info: InstalledExtensionInfo) {
        let packageID = info.packageID
        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: info.uninstallActionID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                router.select(.customize)
            } catch {
                Log.extensions.error("Failed to uninstall extension '\(packageID, privacy: .public)': \(error.localizedDescription)")
                router.notifyError(
                    title: String(localized: "Remove Failed"),
                    message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                )
            }
        }
    }

    private var packageDetailsKey: String {
        guard case .extensionPackage(let id) = router.currentPage else { return "none#\(packageReloadToken)" }
        return "\(id)#\(packageReloadToken)"
    }

    private func loadPackageDetails() async {
        guard case .extensionPackage(let id) = router.currentPage else {
            packageDetails = nil
            return
        }
        packageDetails = await ExtensionPackageDetails.load(packageID: id)
    }

    private func title(for page: SettingsPage) -> String {
        if let title = page.staticTitle { return title }
        switch page {
        case .extensionPackage(let id):
            return InstalledExtensionInfo.info(for: id, in: coordinator.actions)?.name ?? id
        case .action(let id), .builtinAction(let id):
            guard let action = coordinator.actions.first(where: { $0.id == id }) else {
                return String(localized: "Configure Action")
            }
            return customizationManager.presented(action, surface: .table).title
        case .aiPreset(let id):
            guard let preset = aiManager.presets.first(where: { $0.id == id }) else {
                return String(localized: "Edit AI Action")
            }
            return customizationManager.displayTitle(for: AIAction(presetID: id, title: preset.title))
        default:
            return page.id
        }
    }

    // MARK: - Sidebar

    private var systemRows: [SettingsSidebarRow] {
        SettingsPage.systemPages.map { SettingsSidebarRow(systemPage: $0) }
    }

    private var preferencesSearchEntries: [PreferencesSearchEntry] {
        var entries = SettingsPage.systemPages.map { page in
            PreferencesSearchEntry.page(
                id: "page:\(page.id)",
                title: page.staticTitle ?? page.id,
                breadcrumb: String(localized: "Settings"),
                aliases: [englishTitle(for: page)],
                path: [page]
            )
        }

        let generalControls: [(String, String)] = [
            (GeneralSearchTarget.appearAutomatically, "Appear Automatically"),
            (GeneralSearchTarget.holdMouseToTrigger, "Hold Mouse to Trigger"),
            (GeneralSearchTarget.commandPalette, "Command Palette"),
            (GeneralSearchTarget.captureText, "Capture Text"),
            (GeneralSearchTarget.captureTextAutoCopy, "Copy to Clipboard Automatically"),
            (GeneralSearchTarget.saveLocation, "Save Location"),
            (GeneralSearchTarget.playCopySound, "Play Sound on Copy"),
            (GeneralSearchTarget.showMenuBarIcon, "Show Menu Bar Icon"),
            (GeneralSearchTarget.startAtLogin, "Start at Login"),
            (GeneralSearchTarget.accessibilityAccess, "Accessibility Access"),
            (GeneralSearchTarget.screenRecordingAccess, "Screen Recording Access")
        ]
        entries.append(contentsOf: generalControls.map { control in
            .generalControl(
                id: control.0,
                title: String(localized: String.LocalizationValue(control.1)),
                aliases: [control.1]
            )
        })

        let actions = coordinator.actions
        let packageInfos = InstalledExtensionInfo.all(from: actions)
        let packageNames = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.packageID, $0.name) })
        let groupIDs = Set(coordinator.actionGroupDefs.map(\.id))
        var seenPresetIDs = Set<String>()

        for action in actions {
            if ActionIdentity.isAIPreset(action) {
                if let preset = aiManager.preset(forActionID: action.id) {
                    seenPresetIDs.insert(preset.id)
                    appendPreset(preset, to: &entries)
                }
                continue
            }
            if action.chrome.launchesAI { continue }
            if groupIDs.contains(action.id), let group = coordinator.actionGroupDefs.first(where: { $0.id == action.id }) {
                let alias = bindingStore.alias(for: action.id)
                entries.append(.page(
                    id: "custom-group:\(group.id)",
                    title: customizationManager.presented(action, surface: .table).title,
                    breadcrumb: String(localized: "Actions"),
                    aliases: [alias].compactMap { $0 },
                    path: [.customize, .action(id: action.id)],
                    section: .actions
                ))
                continue
            }

            let packageID = ActionIdentity.extensionPackageID(of: action)
            let packageName = packageID.flatMap { packageNames[$0] }
            if case .extensionPkg = action.chrome.source,
               action.chrome.popupBehavior == .showSubActions {
                guard let packageID else { continue }
                entries.append(.page(
                    id: "extension-package:\(packageID)",
                    title: packageName ?? action.title,
                    breadcrumb: String(localized: "Extensions"),
                    aliases: [bindingStore.alias(for: action.id)].compactMap { $0 },
                    path: SettingsDestination.path(forPackage: packageID),
                    section: .actions
                ))
                continue
            }
            if action is GatedExtensionAction, let packageID {
                entries.append(.page(
                    id: "extension-package:\(packageID)",
                    title: packageName ?? action.title,
                    breadcrumb: String(localized: "Extensions"),
                    aliases: [bindingStore.alias(for: action.id)].compactMap { $0 },
                    path: SettingsDestination.path(forPackage: packageID),
                    section: .actions
                ))
                continue
            }

            let presentedTitle = customizationManager.presented(action, surface: .table).title
            let alias = bindingStore.alias(for: action.id)
            entries.append(.page(
                id: "action:\(action.id)",
                title: presentedTitle,
                breadcrumb: packageName.map { "\(String(localized: "Extensions")) › \($0)" }
                    ?? String(localized: "Actions"),
                aliases: [alias].compactMap { $0 },
                path: SettingsDestination.path(for: action),
                section: .actions
            ))
        }

        for preset in aiManager.presets where !seenPresetIDs.contains(preset.id) {
            appendPreset(preset, to: &entries)
        }
        return entries
    }

    private func appendPreset(_ preset: AIActionPreset, to entries: inout [PreferencesSearchEntry]) {
        let actionID = "ai.preset.\(preset.id)"
        entries.append(.page(
            id: "ai-preset:\(preset.id)",
            title: customizationManager.displayTitle(for: AIAction(presetID: preset.id, title: preset.title)),
            breadcrumb: String(localized: "AI"),
            aliases: [bindingStore.alias(for: actionID)].compactMap { $0 },
            path: [.ai, .aiPreset(id: preset.id)],
            section: .actions
        ))
    }

    private func englishTitle(for page: SettingsPage) -> String {
        switch page {
        case .general: return "General"
        case .appearance: return "Customize"
        case .customize: return "Actions"
        case .ai: return "AI"
        case .appRules: return "App Rules"
        case .store: return "Store"
        case .about: return "About"
        default: return page.id
        }
    }

    private var sidebarSelection: Binding<SettingsPage?> {
        Binding(
            get: {
                switch router.sidebarPage {
                case .general:
                    return .general
                case .appearance:
                    return .appearance
                case .customize, .shortcuts, .extensionPackage, .builtinAction, .customActions,
                     .action, .newCustomAction, .newGroup, .iconPicker:
                    return .customize
                case .ai, .aiPreset, .aiNewPreset:
                    return .ai
                case .appRules, .addApplication:
                    return .appRules
                case .store:
                    return .store
                case .about:
                    return .about
                }
            },
            set: { newValue in
                if let newValue { router.select(newValue) }
            }
        )
    }

    private var sidebar: some View {
        SettingsSidebar(
            selection: sidebarSelection,
            systemRows: systemRows,
            searchEntries: preferencesSearchEntries,
            onOpenSearchResult: openSearchResult,
            onSearchStore: { query in
                storeViewModel.searchQuery = query
                router.select(.store)
                storeViewModel.queryDidChange()
            }
        )
        .id(systemColorsToken)
    }

    private func openSearchResult(_ result: PreferencesSearchEntry) {
        switch result.target {
        case .page(let path): router.show(path: path)
        case .generalControl(let id): router.revealGeneralControl(id)
        }
    }

    // MARK: - Detail Card

    private var detail: some View {
        VStack(spacing: 0) {
            detailTopBar

            ZStack(alignment: .top) {
                SettingsNavigationStack(path: router.path) { page in
                    content(for: page)
                }

                if let notice = router.notice {
                    SettingsNoticeBanner(
                        notice: notice,
                        onDismiss: { router.dismissNotice() },
                        onConfirm: { router.confirmNotice() }
                    )
                    .id(notice.id)
                    .zIndex(10)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsDesignTokens.detailCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsDesignTokens.detailCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesignTokens.detailCardRadius, style: .continuous)
                .strokeBorder(SettingsDesignTokens.detailCardBorder, lineWidth: 0.5)
        )
        .padding(.top, SettingsDesignTokens.detailCardInset)
        .padding(.trailing, SettingsDesignTokens.detailCardInset)
        .padding(.bottom, SettingsDesignTokens.detailCardInset)
        .background(navigationShortcuts)
    }

    private var detailTopBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    router.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .opacity(router.canGoBack ? 0.9 : 0.28)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!router.canGoBack)

                Rectangle()
                    .fill(SettingsDesignTokens.rowDivider)
                    .frame(width: 1, height: 14)

                Button {
                    router.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .opacity(router.canGoForward ? 0.9 : 0.28)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!router.canGoForward)
            }
            .settingsGlassCapsule()

            if router.path.count > 1 {
                Text(title(for: router.currentPage))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .lineLimit(1)
            }

            Spacer()

            trailingTopBarControls
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(height: 48)
    }

    @ViewBuilder
    private var trailingTopBarControls: some View {
        HStack(spacing: 8) {
            if let toggle = toolbarModel.pageToggle {
                HStack(spacing: 8) {
                    Text(toggle.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.primaryText)
                    Toggle("", isOn: Binding(
                        get: { toggle.isOn },
                        set: { setPageToggle($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .settingsGlassCapsule(interactive: false)
            }

            let plusItems = PreferencesPlusMenu.items(for: router.currentPage)
            if !plusItems.isEmpty {
                if plusItems.count == 1, let only = plusItems.first {
                    Button {
                        toolbarModel.actions.send(only.action)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: only.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(only.title)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .settingsGlassCapsule()
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        ForEach(plusItems, id: \.title) { item in
                            if item.startsGroup {
                                Divider()
                            }
                            Button {
                                toolbarModel.actions.send(item.action)
                            } label: {
                                Label(item.title, systemImage: item.symbol)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text(String(localized: "Add"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .settingsGlassCapsule()
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if router.currentPage == .store {
                searchField(
                    text: $storeViewModel.searchQuery,
                    isLoading: storeViewModel.isLoading,
                    placeholder: String(localized: "Search extensions..."),
                    help: String(localized: "Search Extensions"),
                    onSubmit: {
                        Task {
                            await storeViewModel.loadAll(limit: Constants.storeFullCatalogLimit, keepPrevious: true)
                        }
                    }
                )

                Button {
                    Task { await storeViewModel.refreshCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .frame(width: 28, height: 28)
                        .settingsGlassCircle()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(storeViewModel.isLoading)

                Menu {
                    ForEach(StoreSort.allCases) { sort in
                        Button {
                            storeViewModel.selectedSort = sort
                        } label: {
                            if storeViewModel.selectedSort == sort {
                                Label(sort.title, systemImage: "checkmark")
                            } else {
                                Text(sort.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text(storeViewModel.selectedSort.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(SettingsDesignTokens.navPillForeground)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .settingsGlassCapsule()
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if router.currentPage == .customize || router.currentPage == .shortcuts {
                searchField(
                    text: $customizeQuery,
                    placeholder: String(localized: "Search actions..."),
                    help: String(localized: "Search Actions")
                )
            }

            if !toolbarModel.pageMenuItems.isEmpty {
                Menu {
                    ForEach(toolbarModel.pageMenuItems) { item in
                        if item.isSeparator {
                            Divider()
                        } else {
                            Button(role: item.role == .destructive ? .destructive : nil) {
                                runPageMenuItem(item.id)
                            } label: {
                                if !item.symbol.isEmpty {
                                    Label(item.title, systemImage: item.symbol)
                                } else {
                                    Text(item.title)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .frame(width: 28, height: 28)
                        .settingsGlassCircle()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func searchField(
        text: Binding<String>,
        isLoading: Bool = false,
        placeholder: String,
        help: String,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        if isSearchExpanded || !text.wrappedValue.isEmpty {
            HStack(spacing: 6) {
                if isLoading && !text.wrappedValue.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 8)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                        .padding(.leading, 8)
                }

                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .focused($isSearchFocused)
                    .onSubmit { onSubmit?() }
                    .onKeyPress(.escape) {
                        if !text.wrappedValue.isEmpty {
                            text.wrappedValue = ""
                            return .handled
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                isSearchExpanded = false
                                isSearchFocused = false
                            }
                            return .handled
                        }
                    }

                if !text.wrappedValue.isEmpty {
                    Button {
                        text.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isSearchExpanded = false
                            isSearchFocused = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }
            }
            .frame(width: 180, height: 28)
            .settingsGlassCapsule(interactive: false)
            // TextField only exists once this branch renders, so focus it here, not in the expand button.
            .onAppear {
                if isSearchExpanded {
                    isSearchFocused = true
                }
            }
            .onChange(of: isSearchFocused) { _, focused in
                if !focused && text.wrappedValue.isEmpty {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isSearchExpanded = false
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)),
                removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .trailing))
            ))
        } else {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isSearchExpanded = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.navPillForeground)
                    .frame(width: 28, height: 28)
                    .settingsGlassCircle()
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(help)
            .transition(.opacity)
        }
    }

    /// ⌘[ and ⌘] for back and forward.
    private var navigationShortcuts: some View {
        Group {
            Button("") { router.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!router.canGoBack)
            Button("") { router.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!router.canGoForward)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func content(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralTab()
                .settingsPaneWidth()
        case .appearance:
            AppearanceTab()
                .settingsPaneWidth()
        case .customize, .shortcuts:
            CustomizePage(
                selectedRowIDs: $selectedRowIDs,
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages,
                query: $customizeQuery
            )
            .frame(maxWidth: Self.customizeListMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .appRules:
            AppRulesTab()
                .settingsPaneWidth()
        case .store:
            ExtensionStoreView(viewModel: storeViewModel)
                .settingsPaneWidth(SettingsLayout.storeMaxWidth)
        case .about:
            AboutTab()
                .settingsPaneWidth()
        case .ai:
            AIPage()
                .settingsPaneWidth()
        case .extensionPackage(let id):
            if let info = InstalledExtensionInfo.info(for: id, in: coordinator.actions),
               info.commands.count == 1,
               !info.isGroup,
               let singleAction = info.commands.first {
                ActionEditorPage(
                    action: singleAction,
                    isSidebarPage: false,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                )
            } else {
                ExtensionPackagePage(
                    packageID: id,
                    details: packageDetails?.packageID == id ? packageDetails : nil,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                )
                .settingsPaneWidth()
            }
        case .builtinAction(let id):
            if let action = coordinator.actions.first(where: { $0.id == id }) {
                ActionEditorPage(
                    action: action,
                    isSidebarPage: false,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                )
            } else {
                Color.clear.onAppear { router.select(.customize) }
            }
        case .customActions:
            CustomActionsPage(
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages
            )
            .settingsPaneWidth()
        case .action(let id):
            actionEditor(for: id)
        case .newCustomAction(let kind):
            NewCustomActionPage(initialKind: kind)
        case .newGroup(let memberIDs):
            NewGroupPage(memberActionIDs: memberIDs)
        case .iconPicker:
            IconPickerPage()
        case .aiPreset(let id):
            if let preset = aiManager.presets.first(where: { $0.id == id }) {
                ActionEditorPage(
                    action: AIAction(presetID: id, title: preset.title),
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                )
            } else {
                Color.clear.onAppear { router.pop() }
            }
        case .aiNewPreset:
            AINewPresetPage()
        case .addApplication:
            AddApplicationPage()
        }
    }

    @ViewBuilder
    private func actionEditor(for id: String) -> some View {
        if let action = coordinator.actions.first(where: { $0.id == id }) {
            if action.chrome.rowStyle == .actionGroup {
                GroupEditorPage(groupID: action.id)
            } else {
                ActionEditorPage(
                    action: action,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                )
            }
        } else {
            Color.clear.onAppear { router.pop() }
        }
    }
}
