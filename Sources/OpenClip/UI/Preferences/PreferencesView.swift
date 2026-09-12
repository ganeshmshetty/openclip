// PreferencesView.swift
// OpenClip
//
// Renders the primary multi-tab preferences window interface for OpenClip.
// The chrome is deliberately stock AppKit/SwiftUI — a sidebar `List` and a
// system toolbar — so the window inherits System Settings' look, vibrancy and
// dark-mode behaviour instead of re-implementing them.
import SwiftUI
import Core
import KeyboardShortcuts

public enum PreferenceTab: String, CaseIterable, Hashable, Sendable {
    case general = "General"
    case appearance = "Appearance"
    case actions = "Actions"
    case store = "Store"
    case appRules = "App Rules"
    case about = "About"
    
    public var localizedTitle: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .actions: return "bolt.horizontal.fill"
        case .store: return "bag.fill"
        case .appRules: return "shield.checkerboard"
        case .about: return "info.circle.fill"
        }
    }

    /// The window's title for this pane. The window is titled after whatever is
    /// on screen, the way every stock settings window is — "OpenClip Preferences"
    /// on all six panes said nothing about where you were.
    public var windowTitle: String {
        String(localized: String.LocalizationValue(rawValue))
    }

    /// Sidebar symbol tint, matching System Settings' coloured glyph tiles.
    public var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .actions: return .orange
        case .store: return .blue
        case .appRules: return .indigo
        case .about: return .teal
        }
    }
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the detail area. Keeps Actions/Appearance
    /// compact and aligned with the window rather than stretching infinitely.
    private static let detailContentMaxWidth: CGFloat = 520

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    @State private var selectedTab: PreferenceTab
    @State private var activeSheet: PreferencesSheet?
    @State private var showingAddActionSheet = false
    @State private var showingCreateGroupSheet = false
    @State private var showingAppPicker = false
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared
    /// Owned by the window (StatusBarController) so the AppKit toolbar and these
    /// panes talk to the same object; the fallback instance is only for the
    /// SwiftUI `Settings` scene, which has no toolbar of its own.
    @ObservedObject private var toolbarModel: PreferencesToolbarModel

    public init(
        initialTab: PreferenceTab = .general,
        toolbarModel: PreferencesToolbarModel = PreferencesToolbarModel()
    ) {
        _selectedTab = State(initialValue: initialTab)
        _toolbarModel = ObservedObject(wrappedValue: toolbarModel)
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .minimumWindowContentSize(width: 900, height: 520)
        // Left at the system default: `.balanced` lets the detail column push
        // into the sidebar's width, which is the case that runs out of room
        // first when the window is dragged narrow.
        .navigationSplitViewStyle(.automatic)
        // No frame here on purpose: the window owns its size (see
        // StatusBarController.showPreferences). Wrapping the split view in a
        // frame makes SwiftUI lay it out as ordinary content inside the window
        // rather than as the window's own split view.
        .onAppear {
            toolbarModel.tab = selectedTab
            loadDisabledState()
            Task {
                await storeViewModel.resetAndFetch(limit: 100)
                await ExtensionUpdateManager.shared.checkForUpdates()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            toolbarModel.tab = newTab
            if newTab == .store && storeViewModel.extensions.isEmpty {
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
            // AI settings live in the inspector now, so a request to configure them selects the
            // row rather than stacking a modal copy on the window.
            if action.chrome.launchesAI {
                selectedTab = .actions
                ActionInspectorModel.shared.inspectedID = action.id
            } else {
                activeSheet = .configure(action: action, request: request)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipSelectPreferencesTab)) { notification in
            if let tab = notification.object as? PreferenceTab {
                selectedTab = tab
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

    // MARK: - Sidebar

    /// `List` selection is optional by contract; the tab itself never is, so a
    /// nil write (Escape, clicking empty space) keeps the current tab.
    private var sidebarSelection: Binding<PreferenceTab?> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if let newValue { selectedTab = newValue }
            }
        )
    }

    private var sidebar: some View {
        List(PreferenceTab.allCases, id: \.self, selection: sidebarSelection) { tab in
            Label {
                Text(tab.localizedTitle)
            } icon: {
                Image(systemName: tab.icon)
                    .foregroundStyle(tab.tint)
            }
            .accessibilityLabel(tab.localizedTitle)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFooter
        }
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
            .frame(minWidth: 680, minHeight: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .general:
            GeneralTab()
        case .appearance:
            AppearanceTab()
        case .actions:
            // No width cap here, unlike the Form-based panes: the Actions pane is a list plus an
            // inspector, and both want the column.
            ActionsTab(
                disabledActionIDs: $disabledActionIDs,
                disabledPackages: $disabledPackages,
                showingAddActionSheet: $showingAddActionSheet,
                showingCreateGroupSheet: $showingCreateGroupSheet
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Single sheet route for Preferences presentations: editing an action's configuration.
private enum PreferencesSheet: Identifiable {
    case configure(action: any Action, request: ConfigurationRequest?)

    var id: String {
        switch self {
        case .configure(let action, _): return "configure:\(action.id)"
        }
    }
}
