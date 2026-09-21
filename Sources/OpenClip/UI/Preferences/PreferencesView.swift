// PreferencesView.swift
// OpenClip
//
// The Settings window: a modern Liquid Glass window layout:
// - Near-black window background with native traffic lights top-left over the sidebar.
// - Fixed-width sidebar sitting directly on the window background (no card/border/shadow).
// - Capsule search field below traffic lights.
// - Colored rounded-square icon tiles for all pages.
// - Subtle translucent row selection highlight (not accent color).
// - Inset rounded detail card with back/forward glass capsule, page title, and trailing pill actions.

import SwiftUI
import Combine
import Core
import KeyboardShortcuts

/// The public vocabulary for opening the window on a page (the status item, the notification
/// other parts of the app post). Maps onto the router's sidebar pages.
public enum PreferenceTab: String, CaseIterable, Hashable, Sendable {
    case general = "General"
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

    /// The window's title for this pane.
    public var windowTitle: String {
        page.staticTitle ?? String(localized: String.LocalizationValue(rawValue))
    }

    /// The sidebar page this tab names.
    public var page: SettingsPage {
        switch self {
        case .general: return .general
        case .appearance: return .appearance
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
    /// The Actions list measure.
    private static let customizeListMaxWidth: CGFloat = SettingsLayout.contentMaxWidth

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    /// The Customize list's selection, kept here so the toolbar's New Group can seed a group with it.
    @State private var selectedRowIDs: Set<String> = []
    /// The Customize list's search text.
    @State private var customizeQuery = ""
    @State private var sidebarQuery = ""
    /// The folder, manifest and README of the extension whose page is on screen.
    @State private var packageDetails: ExtensionPackageDetails?
    /// Bumped when extensions change.
    @State private var packageReloadToken = 0
    /// Bumped when system settings change.
    @State private var systemColorsToken = 0
    @State private var isStoreSearchExpanded = false
    @FocusState private var isStoreSearchFocused: Bool
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var aiManager = AIServiceManager.shared
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
            loadDisabledState()
            Task {
                await storeViewModel.resetAndFetch(limit: 100)
                await ExtensionUpdateManager.shared.checkForUpdates()
            }
        }
        .task(id: packageDetailsKey) {
            await loadPackageDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipExtensionsDidChange)) { _ in
            packageReloadToken += 1
            loadDisabledState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
            systemColorsToken += 1
        }
        .onChange(of: router.path) { _, newPath in
            syncToolbar()
            if newPath.last == .store && storeViewModel.extensions.isEmpty {
                Task {
                    await storeViewModel.resetAndFetch(limit: 100)
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
            saveDisabledState()
            syncToolbar()
        }
        .onChange(of: disabledPackages) { _, _ in
            saveDisabledState()
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
            return SettingsToolbarToggle(
                isOn: info.gatedReason == nil && !disabledPackages.contains(id),
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
                disabledPackages: $disabledPackages
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
            return aiManager.presets.first(where: { $0.id == id })?.title ?? String(localized: "Edit AI Action")
        default:
            return page.id
        }
    }

    // MARK: - Sidebar

    private var systemRows: [SettingsSidebarRow] {
        SettingsPage.systemPages.map { SettingsSidebarRow(systemPage: $0) }
    }

    private var secondGroupRows: [SettingsSidebarRow] {
        var rows: [SettingsSidebarRow] = [
            SettingsSidebarRow(
                page: .ai,
                title: SettingsPage.ai.staticTitle ?? "AI",
                keywords: SettingsPage.ai.searchKeywords,
                tile: .bare(.symbol(SettingsPage.ai.systemImage)),
                isDisabled: !aiManager.isAIEnabled
            )
        ]

        for action in coordinator.actions where ActionIdentity.isBuiltin(action)
            && !action.chrome.launchesAI
            && action.chrome.rowStyle != .actionGroup {
            let presentation = customizationManager.presented(action, surface: .table)
            let isActionDisabled = disabledActionIDs.contains(action.id)
            rows.append(SettingsSidebarRow(
                page: .builtinAction(id: action.id),
                title: presentation.title,
                keywords: action.keywords + [action.id],
                tile: .bare(SettingsHeroHeader.glyph(for: action, presented: presentation)),
                isDisabled: isActionDisabled
            ))
        }

        for info in InstalledExtensionInfo.all(from: coordinator.actions) {
            var keywords = info.commands.map { customizationManager.presented($0, surface: .table).title }
            keywords.append(contentsOf: info.commands.flatMap(\.keywords))
            keywords.append(info.packageID)
            let isPkgDisabled = disabledPackages.contains(info.packageID)
                || info.gatedReason != nil
                || (!info.commands.isEmpty && info.commands.allSatisfy { disabledActionIDs.contains($0.id) })
            rows.append(SettingsSidebarRow(
                page: .extensionPackage(id: info.packageID),
                title: info.name,
                keywords: keywords,
                tile: .bare(Self.plainGlyph(info.icon)),
                isDisabled: isPkgDisabled
            ))
        }

        let customTitles = coordinator.actions
            .filter { SettingsDestination.isCustomAction($0) }
            .map { customizationManager.presented($0, surface: .table).title }
        rows.append(SettingsSidebarRow(
            page: .customActions,
            title: SettingsPage.customActions.staticTitle ?? "",
            keywords: SettingsPage.customActions.searchKeywords + customTitles,
            tile: .bare(.symbol(SettingsPage.customActions.systemImage))
        ))

        return SettingsSidebarOrder.sorted(rows)
    }

    private static func plainGlyph(_ icon: ActionIcon) -> ActionIcon {
        if case .text(let text) = icon, text.count > 2 {
            return .symbol("puzzlepiece.extension")
        }
        return icon
    }

    private var sidebarSelection: Binding<SettingsPage?> {
        Binding(
            get: { router.sidebarPage },
            set: { newValue in
                if let newValue { router.select(newValue) }
            }
        )
    }

    private var sidebar: some View {
        SettingsSidebar(
            selection: sidebarSelection,
            query: $sidebarQuery,
            systemRows: systemRows,
            extensionRows: secondGroupRows
        )
        .id(systemColorsToken)
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
            // Glass capsule with < | >
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
            .background(
                Capsule()
                    .fill(SettingsDesignTokens.navPillBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5)
            )

            // Current sub-page title next to chevrons when drilled in
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
                .background(Capsule().fill(SettingsDesignTokens.navPillBackground))
                .overlay(Capsule().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
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
                        .background(Capsule().fill(SettingsDesignTokens.navPillBackground))
                        .overlay(Capsule().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
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
                        .background(Capsule().fill(SettingsDesignTokens.navPillBackground))
                        .overlay(Capsule().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
            }

            if router.currentPage == .store {
                storeSearchField

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
                    .background(Capsule().fill(SettingsDesignTokens.navPillBackground))
                    .overlay(Capsule().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Button {
                    Task { await storeViewModel.refreshCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.navPillForeground)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(SettingsDesignTokens.navPillBackground))
                        .overlay(Circle().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(storeViewModel.isLoading)
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
                        .background(Circle().fill(SettingsDesignTokens.navPillBackground))
                        .overlay(Circle().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var storeSearchField: some View {
        if isStoreSearchExpanded || !storeViewModel.searchQuery.isEmpty {
            HStack(spacing: 6) {
                if storeViewModel.isLoading && !storeViewModel.searchQuery.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 8)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.sidebarSearchPlaceholder)
                        .padding(.leading, 8)
                }

                TextField(String(localized: "Search extensions..."), text: $storeViewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .focused($isStoreSearchFocused)
                    .onSubmit {
                        Task {
                            await storeViewModel.resetAndFetch(limit: 100, keepPrevious: true)
                        }
                    }
                    .onKeyPress(.escape) {
                        if !storeViewModel.searchQuery.isEmpty {
                            storeViewModel.searchQuery = ""
                            return .handled
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                isStoreSearchExpanded = false
                                isStoreSearchFocused = false
                            }
                            return .handled
                        }
                    }

                if !storeViewModel.searchQuery.isEmpty {
                    Button {
                        storeViewModel.searchQuery = ""
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
                            isStoreSearchExpanded = false
                            isStoreSearchFocused = false
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
            .background(Capsule().fill(SettingsDesignTokens.navPillBackground))
            .overlay(Capsule().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
            .onChange(of: isStoreSearchFocused) { _, focused in
                if !focused && storeViewModel.searchQuery.isEmpty {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isStoreSearchExpanded = false
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
                    isStoreSearchExpanded = true
                    isStoreSearchFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.navPillForeground)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(SettingsDesignTokens.navPillBackground))
                    .overlay(Circle().strokeBorder(SettingsDesignTokens.navPillBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Search Extensions"))
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
                ActionEditorPage(action: singleAction, isSidebarPage: true)
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
                ActionEditorPage(action: action, isSidebarPage: true)
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
            AIPresetPage(presetID: id)
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
                ActionEditorPage(action: action)
            }
        } else {
            Color.clear.onAppear { router.pop() }
        }
    }

    private func loadDisabledState() {
        disabledActionIDs = DefaultSettingsStore.shared.get(.disabledActionIDs)
        disabledPackages = DefaultSettingsStore.shared.get(.disabledPackages)
    }

    private func saveDisabledState() {
        DefaultSettingsStore.shared.set(.disabledActionIDs, value: disabledActionIDs)
        DefaultSettingsStore.shared.set(.disabledPackages, value: disabledPackages)
    }
}
