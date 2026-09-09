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
    @StateObject private var storeViewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init(initialTab: PreferenceTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        // No frame here on purpose: the window owns its size (see
        // StatusBarController.showPreferences). Wrapping the split view in a
        // frame makes SwiftUI lay it out as ordinary content inside the window
        // rather than as the window's own split view.
        .onAppear {
            loadDisabledState()
            Task {
                await storeViewModel.resetAndFetch(limit: 100)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .store && storeViewModel.extensions.isEmpty {
                Task {
                    await storeViewModel.resetAndFetch(limit: 100)
                }
            }
        }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledState() }
        .onChange(of: disabledPackages) { _, _ in saveDisabledState() }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenActionConfiguration)) { notification in
            guard let request = notification.userInfo?["request"] as? ConfigurationRequest,
                  let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            activeSheet = .configure(action: action, request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipSelectPreferencesTab)) { notification in
            if let tab = notification.object as? PreferenceTab {
                selectedTab = tab
            }
        }
        .sheet(item: $activeSheet) { route in
            switch route {
            case .configure(let action, let request):
                if action.chrome.launchesAI {
                    ConfigureAISheet()
                } else {
                    EditActionSheet(action: action, configurationRequest: request)
                }
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
        .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 260)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(Text(selectedTab.localizedTitle))
            .toolbar { toolbarContent }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
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
        case .store:
            ExtensionStoreView(viewModel: storeViewModel)
        case .appRules:
            AppRulesTab()
        case .about:
            // AboutTab caps its own column width and already fills the pane.
            AboutTab()
        }
    }

    /// One toolbar item, always. Publishing items only on some tabs let SwiftUI
    /// tear the window's toolbar down on the tabs that had none, and a window
    /// that gains and loses its toolbar re-measures its title bar each time —
    /// which is what pushed the traffic lights out of the sidebar on the way in
    /// and out of General, Appearance and About. The item stays put and only its
    /// contents change.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            switch selectedTab {
            case .actions:
                addMenu
            case .store:
                refreshButton
            default:
                // A zero-size placeholder: the item has to exist for the toolbar
                // to, but there is nothing to act on from these tabs.
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                showingCreateGroupSheet = true
            } label: {
                Label(String(localized: "New Group"), systemImage: "folder.badge.plus")
            }

            Button {
                showingAddActionSheet = true
            } label: {
                Label(String(localized: "Add Custom Action"), systemImage: "plus.circle")
            }

            Button {
                presentInstallExtensionPanel()
            } label: {
                Label(String(localized: "Install Extension…"), systemImage: "square.and.arrow.down")
            }
        } label: {
            Label(String(localized: "Add"), systemImage: "plus")
        }
        .help(String(localized: "Add Action or Group"))
    }

    private var refreshButton: some View {
        Button {
            Task {
                await storeViewModel.refreshCatalog()
            }
        } label: {
            if storeViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(String(localized: "Refresh Catalog"), systemImage: "arrow.clockwise")
            }
        }
        .disabled(storeViewModel.isLoading)
        .help(String(localized: "Refresh Catalog"))
        .accessibilityLabel(String(localized: "Refresh Catalog"))
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
