// PreferencesView.swift
// OpenClip
//
// Renders the primary multi-pane preferences window interface for OpenClip.
// The chrome is deliberately stock AppKit/SwiftUI — a sidebar `List` and a
// system toolbar — so the window inherits System Settings' look, vibrancy and
// dark-mode behaviour instead of re-implementing them.
//
// What the window shows is decided by `SettingsRouter`, not by which layer was
// opened last: every destination, including a single action's settings, is a
// route the sidebar can point at. See `SettingsRouter.swift` for why.
import SwiftUI
import Core
import KeyboardShortcuts

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

    /// The window's title for this pane. The window is titled after whatever is
    /// on screen, the way every stock settings window is.
    public var windowTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }

    /// The route this tab names. `PreferenceTab` stays the public vocabulary for
    /// the status item and the tab-selection notification; the router is what the
    /// window actually follows.
    var page: SettingsPage {
        switch self {
        case .general: return .general
        case .appearance: return .appearance
        case .actions: return .actions
        case .shortcuts: return .shortcuts
        case .ai: return .ai
        case .store: return .store
        case .appRules: return .appRules
        case .about: return .about
        }
    }

    /// The tab a route belongs to, for the toolbar's title. An action's page is
    /// titled after the action itself, so it has no tab.
    static func from(_ page: SettingsPage) -> PreferenceTab? {
        allCases.first { $0.page == page }
    }
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the Form-based panes. Keeps them compact and
    /// aligned with the window rather than stretching infinitely.
    private static let detailContentMaxWidth: CGFloat = 520

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    @State private var activeSheet: PreferencesSheet?
    @State private var showingAddActionSheet = false
    @State private var showingCreateGroupSheet = false
    @State private var showingAppPicker = false
    /// Sidebar filter. Settings are only findable if you already know which pane
    /// they are on, which is the other half of the navigation problem.
    @State private var sidebarQuery = ""
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var router = SettingsRouter.shared
    /// Owned by the window (StatusBarController) so the AppKit toolbar and these
    /// panes talk to the same object; the fallback instance is only for the
    /// SwiftUI `Settings` scene, which has no toolbar of its own.
    @ObservedObject private var toolbarModel: PreferencesToolbarModel

    /// Route to select the first time this view appears. Applied in `onAppear`, not in `init`:
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
        .navigationSplitViewStyle(.automatic)
        .onAppear {
            if !didApplyInitialPage {
                didApplyInitialPage = true
                router.show(initialPage)
            }
            syncToolbar()
            loadDisabledState()
            Task {
                await storeViewModel.resetAndFetch(limit: 100)
                await ExtensionUpdateManager.shared.checkForUpdates()
            }
        }
        .onChange(of: router.page) { _, newPage in
            syncToolbar()
            if newPage == .store && storeViewModel.extensions.isEmpty {
                Task {
                    await storeViewModel.resetAndFetch(limit: 100)
                }
            }
        }
        // Toolbar <-> panes. The toolbar owns the store's filter and search box,
        // so those travel through the model in both directions.
        .onReceive(toolbarModel.actions) { action in
            switch action {
            case .newGroup: showingCreateGroupSheet = true
            case .addCustomAction: showingAddActionSheet = true
            case .installExtension: presentInstallExtensionPanel()
            case .addApplication: showingAppPicker = true
            case .refresh: Task { await storeViewModel.refreshCatalog() }
            }
        }
        .onChange(of: toolbarModel.storeFilter) { _, filter in
            guard storeViewModel.selectedFilter != filter else { return }
            storeViewModel.selectedFilter = filter
        }
        .onChange(of: storeViewModel.selectedFilter) { _, filter in
            guard toolbarModel.storeFilter != filter else { return }
            toolbarModel.storeFilter = filter
        }
        .onChange(of: toolbarModel.searchQuery) { _, query in
            guard storeViewModel.searchQuery != query else { return }
            storeViewModel.searchQuery = query
            storeViewModel.queryDidChange()
        }
        .onChange(of: storeViewModel.searchQuery) { _, query in
            toolbarModel.searchQuery = query
        }
        .onChange(of: storeViewModel.isLoading) { _, isLoading in
            toolbarModel.isRefreshing = isLoading
        }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledState() }
        .onChange(of: disabledPackages) { _, _ in saveDisabledState() }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenActionConfiguration)) { notification in
            guard let request = notification.userInfo?["request"] as? ConfigurationRequest,
                  let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            // Everything is a route now, so a request to configure an action
            // navigates to it instead of stacking a modal on the window. Only a
            // request that names missing options still needs the sheet, because
            // the sheet is what highlights them.
            if action.chrome.launchesAI {
                router.show(.ai)
            } else if request.missingOptionIDs.isEmpty {
                router.show(.action(id: action.id))
            } else {
                activeSheet = .configure(action: action, request: request)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipSelectPreferencesTab)) { notification in
            if let tab = notification.object as? PreferenceTab {
                router.show(tab.page)
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { bundleID in
                RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: [bundleID]))
            }
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .configure(let action, let request):
                EditActionSheet(action: action, configurationRequest: request)
            }
        }
    }

    private func syncToolbar() {
        toolbarModel.tab = PreferenceTab.from(router.page) ?? .actions
        toolbarModel.pageTitleOverride = pageTitle(for: router.page)
    }

    /// An action's page is titled after the action, not after "Configure Action".
    private func pageTitle(for page: SettingsPage) -> String? {
        guard case .action(let id) = page,
              let action = coordinator.actions.first(where: { $0.id == id }) else { return nil }
        return customizationManager.presented(action, surface: .table).title
    }

    // MARK: - Sidebar

    /// One sidebar row. `isChild` renders an action's page indented under Actions,
    /// which is what tells the window it is one level in.
    private struct SidebarRow: Identifiable {
        let page: SettingsPage
        let title: String
        let icon: String
        let tint: Color
        let isChild: Bool
        var id: String { page.id }
    }

    private var sidebarRows: [SidebarRow] {
        var rows: [SidebarRow] = []
        for page in router.matches(sidebarQuery) {
            rows.append(SidebarRow(
                page: page,
                title: page.title,
                icon: page.icon,
                tint: page.tint,
                isChild: false
            ))
            // The action being configured lives under Actions, where it came from.
            if page == .actions,
               let id = router.lastConfiguredActionID,
               let action = coordinator.actions.first(where: { $0.id == id }) {
                let presentation = customizationManager.presented(action, surface: .table)
                rows.append(SidebarRow(
                    page: .action(id: id),
                    title: presentation.title,
                    icon: SettingsPage.action(id: id).icon,
                    tint: SettingsPage.action(id: id).tint,
                    isChild: true
                ))
            }
        }
        return rows
    }

    /// `List` selection is optional by contract; the route never is, so a nil
    /// write (Escape, clicking empty space) keeps the current page.
    private var sidebarSelection: Binding<SettingsPage?> {
        Binding(
            get: { router.page },
            set: { newValue in
                if let newValue { router.show(newValue) }
            }
        )
    }

    private var sidebar: some View {
        List(sidebarRows, selection: sidebarSelection) { row in
            Label {
                Text(row.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: row.icon)
                    .foregroundStyle(row.tint)
            }
            .padding(.leading, row.isChild ? 16 : 0)
            .tag(row.page)
            .accessibilityLabel(row.title)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarSearch
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
    }

    private var sidebarSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $sidebarQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !sidebarQuery.isEmpty {
                Button {
                    sidebarQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 14) {
            Button {
                if let url = URL(string: "https://www.getopenclip.app/docs") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Documentation")
            .accessibilityLabel("Documentation")

            Button {
                if let url = URL(string: "https://github.com/ganeshmshetty/openclip") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .help("GitHub Repository")
            .accessibilityLabel("GitHub Repository")

            Spacer()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Detail

    private var detail: some View {
        detailContent
            // The detail column's floor, which is what stops the window shrinking:
            // the split view happily collapses the sidebar, so the minimum the
            // window inherits is whatever the content insists on.
            .frame(minWidth: 540, minHeight: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch router.page {
        case .general:
            GeneralTab()
        case .appearance:
            AppearanceTab()
        case .actions:
            ActionsTab(
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages,
                showingAddActionSheet: $showingAddActionSheet,
                showingCreateGroupSheet: $showingCreateGroupSheet
            )
            .frame(maxWidth: Self.detailContentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .action(let id):
            ActionSettingsPane(actionID: id)
                .frame(maxWidth: Self.detailContentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .shortcuts:
            ShortcutsPane()
                .frame(maxWidth: Self.detailContentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ai:
            AIPane()
        case .store:
            ExtensionStoreView(viewModel: storeViewModel)
        case .appRules:
            AppRulesTab(showingAppPicker: $showingAppPicker)
        case .about:
            // AboutTab caps its own column width and already fills the pane.
            AboutTab()
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

/// Single sheet route for Preferences presentations: the configuration request
/// that has to highlight missing options.
private enum PreferencesSheet: Identifiable {
    case configure(action: any Action, request: ConfigurationRequest?)

    var id: String {
        switch self {
        case .configure(let action, _): return "configure:\(action.id)"
        }
    }
}
