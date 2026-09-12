// PreferencesView.swift
// OpenClip
//
// The Settings window: a System Settings style sidebar — search field, OpenClip's pages, then
// AI, every built-in action, every installed extension and the user's custom actions — and a
// detail column that shows whatever the router's path says, with the toolbar's back and forward
// arrows as the way around.
//
// The chrome is deliberately stock AppKit/SwiftUI — a sidebar `List` and a system toolbar — so
// the window inherits System Settings' look, vibrancy and dark-mode behaviour instead of
// re-implementing them. What the window shows is decided by `SettingsRouter`, not by which layer
// was opened last: nothing here floats over anything else.
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
        case .actions: return .customize
        case .shortcuts: return .shortcuts
        case .ai: return .ai
        case .store: return .store
        case .appRules: return .appRules
        case .about: return .about
        }
    }
}

@MainActor
public struct PreferencesView: View {
    /// Widest the Customize list grows; the grouped `Form` pages set their own width.
    private static let customizeListMaxWidth: CGFloat = 640

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    /// The Customize list's selection, kept here so the toolbar's New Group can seed a group with it.
    @State private var selectedRowIDs: Set<String> = []
    @State private var sidebarQuery = ""
    /// The folder, manifest and README of the extension whose page is on screen. Read once, off
    /// the main thread, and used by both the page's hero and the toolbar's ellipsis menu.
    @State private var packageDetails: ExtensionPackageDetails?
    /// Bumped when extensions change, so the details above are read again.
    @State private var packageReloadToken = 0
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var aiManager = AIServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    /// Owned by the window (StatusBarController) so the AppKit toolbar and these
    /// panes talk to the same object; the fallback instance is only for the
    /// SwiftUI `Settings` scene, which has no toolbar of its own.
    @ObservedObject private var toolbarModel: PreferencesToolbarModel

    /// Page to select the first time this view appears. Applied in `onAppear`, not in `init`:
    /// SwiftUI re-evaluates a scene's body freely, and writing the router from an initializer would
    /// throw the user back to General at arbitrary moments.
    private let initialPage: SettingsPage
    @State private var didApplyInitialPage = false

    public init(
        initialTab: PreferenceTab = .general,
        toolbarModel: PreferencesToolbarModel = PreferencesToolbarModel()
    ) {
        initialPage = initialTab.page
        _toolbarModel = ObservedObject(wrappedValue: toolbarModel)
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .minimumWindowContentSize(width: 760, height: 480)
        .hidesTitlebarSeparator()
        // Left at the system default: `.balanced` lets the detail column push
        // into the sidebar's width, which is the case that runs out of room
        // first when the window is dragged narrow.
        .navigationSplitViewStyle(.automatic)
        // No frame here on purpose: the window owns its size (see
        // StatusBarController.showPreferences).
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
        }
        .onChange(of: router.path) { _, newPath in
            syncToolbar()
            if newPath.last == .store && storeViewModel.extensions.isEmpty {
                Task {
                    await storeViewModel.resetAndFetch(limit: 100)
                }
            }
        }
        // The title of an action's or extension's page follows the data it is named after.
        .onReceive(coordinator.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        .onReceive(customizationManager.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        .onReceive(aiManager.objectWillChange.receive(on: RunLoop.main)) { _ in syncToolbar() }
        // Toolbar <-> panes. The toolbar owns the store's filter and search box,
        // so those travel through the model in both directions.
        .onReceive(toolbarModel.actions) { action in
            switch action {
            case .newGroup:
                router.push(.newGroup(
                    memberIDs: CustomizePage.groupCandidates(selectedRowIDs: selectedRowIDs, coordinator: coordinator)
                ))
            case .addCustomAction: router.push(.newCustomAction)
            case .addApplication: router.push(.addApplication)
            case .addAIAction: router.push(.aiNewPreset)
            case .setStoreSort(let sort): storeViewModel.selectedSort = sort
            case .setPageToggle(let isOn): setPageToggle(isOn)
            case .pageMenuItem(let id): runPageMenuItem(id)
            }
        }
        .onChange(of: toolbarModel.searchQuery) { _, query in
            guard storeViewModel.searchQuery != query else { return }
            storeViewModel.searchQuery = query
            storeViewModel.queryDidChange()
        }
        .onChange(of: storeViewModel.searchQuery) { _, query in
            toolbarModel.searchQuery = query
        }
        .onChange(of: storeViewModel.selectedSort) { _, sort in
            guard toolbarModel.storeSort != sort else { return }
            toolbarModel.storeSort = sort
        }
        .onChange(of: storeViewModel.isLoading) { _, isLoading in
            toolbarModel.isRefreshing = isLoading
            // The menu's Refresh greys out while one is running.
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
            // Everything is a route, so a request to configure an action navigates to its page
            // — with the request kept so the page can explain what is missing — instead of
            // stacking a modal on the window.
            router.openConfiguration(for: action, request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipSelectPreferencesTab)) { notification in
            if let tab = notification.object as? PreferenceTab {
                router.select(tab.page)
            }
        }
    }

    // MARK: - Toolbar

    private func syncToolbar() {
        toolbarModel.page = router.currentPage
        toolbarModel.title = title(for: router.currentPage)
        toolbarModel.pageToggle = pageToggle(for: router.currentPage)
        toolbarModel.pageMenuItems = pageMenuItems(for: router.currentPage)
    }

    /// The action a page is about, when it is about one: an action's editor, or a built-in's page.
    private func subjectAction(of page: SettingsPage) -> (any Action)? {
        switch page {
        case .action(let id), .builtinAction(let id):
            return coordinator.actions.first(where: { $0.id == id })
        default:
            return nil
        }
    }

    /// The switch the toolbar shows, trailing, on a page that is about something switchable.
    private func pageToggle(for page: SettingsPage) -> SettingsToolbarToggle? {
        switch page {
        case .ai:
            return SettingsToolbarToggle(
                isOn: aiManager.isAIEnabled,
                label: String(localized: "Enable AI Tools")
            )
        case .extensionPackage(let id):
            guard let info = InstalledExtensionInfo.info(for: id, in: coordinator.actions) else { return nil }
            return SettingsToolbarToggle(
                isOn: info.gatedReason == nil && !disabledPackages.contains(id),
                label: String(localized: "Enable \(info.name)")
            )
        default:
            guard let action = subjectAction(of: page) else { return nil }
            let presentation = customizationManager.presented(action, surface: .table)
            return SettingsToolbarToggle(
                isOn: ActionEnablement.binding(
                    for: action,
                    disabledActionIDs: $disabledActionIDs,
                    disabledPackages: $disabledPackages
                ).wrappedValue,
                label: String(localized: "Enable \(presentation.title)")
            )
        }
    }

    /// Moving the toolbar's switch means whatever it means for the page on screen.
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
            return SettingsToolbarAccessories.storeMenuItems(isRefreshing: storeViewModel.isLoading)
        case .extensionPackage(let id):
            guard InstalledExtensionInfo.info(for: id, in: coordinator.actions) != nil else { return [] }
            let details = packageDetails?.packageID == id ? packageDetails : nil
            return SettingsToolbarAccessories.extensionMenuItems(
                .init(hasReadme: details?.readmeURL != nil, hasFolder: details?.directoryURL != nil)
            )
        default:
            guard let action = subjectAction(of: page) else { return [] }
            return SettingsToolbarAccessories.actionMenuItems(
                .init(
                    canDuplicate: ActionIdentity.canDuplicate(action),
                    canDelete: SettingsDestination.isCustomAction(action)
                )
            )
        }
    }

    /// The window handles what it owns (an extension's files); anything that belongs to a page's
    /// own state is forwarded to it.
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
        guard case .extensionPackage(let id) = router.currentPage,
              let info = InstalledExtensionInfo.info(for: id, in: coordinator.actions) else { return }
        router.confirmDestructive(
            title: String(localized: "Uninstall \(info.name)?"),
            message: String(localized: "Its files and settings are deleted from this Mac."),
            confirmTitle: String(localized: "Uninstall")
        ) {
            uninstallExtension(info)
        }
    }

    private func uninstallExtension(_ info: InstalledExtensionInfo) {
        let name = info.name
        let packageID = info.packageID
        Task {
            do {
                try await ExtensionManager.shared.uninstallExtension(actionID: info.uninstallActionID)
                NotificationCenter.default.post(name: .openClipExtensionsDidChange, object: nil)
                router.select(.customize)
                router.notify(SettingsNotice(
                    title: String(localized: "Extension Removed"),
                    message: String(localized: "\(name) was removed from this Mac."),
                    style: .info
                ))
            } catch {
                Log.extensions.error("Failed to uninstall extension '\(packageID, privacy: .public)': \(error.localizedDescription)")
                router.notifyError(
                    title: String(localized: "Remove Failed"),
                    message: String(localized: "OpenClip could not remove extension: \(error.localizedDescription)")
                )
            }
        }
    }

    // MARK: - Extension package details

    /// Identity of what `packageDetails` should hold: the extension on screen, and the reload
    /// token so an install or removal re-reads the folder.
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

    /// A page's title: fixed for most, taken from the data for an action, an extension or a prompt.
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

    /// The second group: everything that provides actions, one row each — the way Raycast lists
    /// Calculator and Calendar next to third-party extensions. What OpenClip ships comes first
    /// (AI, then the built-in actions, then the user's own), and installed extensions follow; see
    /// `SettingsSidebarOrder`. A row answers a search for any of its actions' names or keywords,
    /// so "verify" finds the JWT extension and "sum" finds Calculate.
    private var secondGroupRows: [SettingsSidebarRow] {
        var rows: [SettingsSidebarRow] = [SettingsSidebarRow(systemPage: .ai)]

        for action in coordinator.actions where ActionIdentity.isBuiltin(action)
            && !action.chrome.launchesAI
            && action.chrome.rowStyle != .actionGroup {
            let presentation = customizationManager.presented(action, surface: .table)
            rows.append(SettingsSidebarRow(
                page: .builtinAction(id: action.id),
                title: presentation.title,
                keywords: action.keywords + [action.id],
                tile: .icon(Self.tileIcon(for: action, presented: presentation), tint: ExtensionTint.color(for: action.id))
            ))
        }

        for info in InstalledExtensionInfo.all(from: coordinator.actions) {
            var keywords = info.commands.map { customizationManager.presented($0, surface: .table).title }
            keywords.append(contentsOf: info.commands.flatMap(\.keywords))
            keywords.append(info.packageID)
            rows.append(SettingsSidebarRow(
                page: .extensionPackage(id: info.packageID),
                title: info.name,
                keywords: keywords,
                tile: .icon(info.icon, tint: ExtensionTint.color(for: info.packageID))
            ))
        }

        let customTitles = coordinator.actions
            .filter { SettingsDestination.isCustomAction($0) }
            .map { customizationManager.presented($0, surface: .table).title }
        rows.append(SettingsSidebarRow(
            page: .customActions,
            title: SettingsPage.customActions.staticTitle ?? "",
            keywords: SettingsPage.customActions.searchKeywords + customTitles,
            tile: .symbol(SettingsPage.customActions.systemImage, tint: SettingsPage.customActions.tint)
        ))

        return SettingsSidebarOrder.sorted(rows)
    }

    /// A built-in's tile glyph. Copy, Cut and Paste draw as text glyphs in the popup bar; their
    /// settings symbol is what a tile can show.
    private static func tileIcon(for action: any Action, presented: ActionPresentationModel) -> ActionIcon {
        if case .text = presented.icon,
           let symbol = (action as? any ConfigurableAction)?.preferenceIconName, !symbol.isEmpty {
            return .symbol(symbol)
        }
        return presented.icon
    }

    /// `List` selection is optional by contract; the page never is, so a nil write (Escape,
    /// clicking empty space) keeps the current page. Selecting the page already shown returns to
    /// its top level, the way clicking a System Settings pane does.
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
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    // MARK: - Detail

    private var detail: some View {
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
        // The detail column's floor, which is what stops the window shrinking:
        // the split view happily collapses the sidebar, so the minimum the
        // window inherits is whatever the content insists on.
        .frame(minWidth: 540, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(navigationShortcuts)
    }

    /// ⌘[ and ⌘] for back and forward, the keys Finder, Safari and System Settings use.
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

    @ViewBuilder
    private func content(for page: SettingsPage) -> some View {
        switch page {
        case .general:
            GeneralTab()
        case .appearance:
            AppearanceTab()
        case .customize:
            CustomizePage(selectedRowIDs: $selectedRowIDs)
                .frame(maxWidth: Self.customizeListMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .shortcuts:
            ShortcutsPage(
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages
            )
        case .appRules:
            AppRulesTab()
        case .store:
            ExtensionStoreView(viewModel: storeViewModel)
        case .about:
            AboutTab()
        case .ai:
            AIPage()
        case .extensionPackage(let id):
            ExtensionPackagePage(
                packageID: id,
                details: packageDetails?.packageID == id ? packageDetails : nil,
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages
            )
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
        case .action(let id):
            actionEditor(for: id)
        case .newCustomAction:
            NewCustomActionPage()
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

    /// An action's editor, or a group's when the id names a group. A subject that went away while
    /// its page was open (uninstalled extension, ungrouped group) sends the window back rather
    /// than showing an empty page.
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
