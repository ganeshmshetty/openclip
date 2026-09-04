// PreferencesView.swift
// OpenClip
//
// Renders the primary multi-tab preferences window interface for OpenClip.
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
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the detail area. Keeps Actions/Appearance
    /// compact and aligned with the window rather than stretching infinitely.
    private static let detailContentMaxWidth: CGFloat = 480

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
        HStack(spacing: 0) {
            // Seamless Sidebar
            VStack(alignment: .leading, spacing: 4) {
                // Top spacing so the window traffic lights (close/minimize/expand)
                // float seamlessly over the sidebar without covering the first tab item.
                Spacer()
                    .frame(height: 36)
                
                ForEach(PreferenceTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 18)
                            Text(tab.localizedTitle)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .background(
                            selectedTab == tab ?
                            Color.accentColor : Color.clear
                        )
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.localizedTitle)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
                
                Spacer()
                
                // Bottom footer icons (Help and GitHub - NO TEXT)
                HStack(spacing: 14) {
                    Button(action: {
                        if let url = URL(string: "https://www.getopenclip.app/docs") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Documentation")
                    .accessibilityLabel("Documentation")
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/ganeshmshetty/openclip") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("GitHub Repository")
                    .accessibilityLabel("GitHub Repository")
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 200)
            .background(Color.primary.opacity(0.02))
            
            Divider()
                .opacity(0.3)
            
            // Detail Area
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(selectedTab.localizedTitle)
                        .font(.system(size: 20, weight: .bold))
                    
                    Spacer()

                    if selectedTab == .actions {
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
                        .menuStyle(.button)
                        .help(String(localized: "Add Action or Group"))
                    } else if selectedTab == .store {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                            TextField(String(localized: "Search extensions..."), text: $storeViewModel.searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .onChange(of: storeViewModel.searchQuery) { _, _ in
                                    storeViewModel.queryDidChange()
                                }
                            if storeViewModel.isLoading && !storeViewModel.extensions.isEmpty {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                        .frame(width: 200)
                    }
                }
                .frame(maxWidth: selectedTab == .store ? .infinity : Self.detailContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                Group {
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
                    case .store:
                        ExtensionStoreView(viewModel: storeViewModel)
                    case .appRules: 
                        AppRulesTab()
                    case .about: 
                        AboutTab()
                    }
                }
                .frame(maxWidth: selectedTab == .store ? .infinity : Self.detailContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, selectedTab == .store ? 20 : 16)
                // General, Appearance, Actions, and Store run edge-to-edge to the window bottom; other tabs keep breathing room.
                .padding(.bottom, (selectedTab == .general || selectedTab == .appearance || selectedTab == .actions || selectedTab == .store) ? 0 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 760, idealWidth: 760, minHeight: 520, idealHeight: 620)
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
