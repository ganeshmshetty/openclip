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
    case ai = "AI"
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
        case .ai: return Constants.defaultAIIconSymbol
        case .appRules: return "shield.checkerboard"
        case .about: return "info.circle.fill"
        }
    }
}

/// Sub-tab selector for the Actions tab (Actions | Store).
enum ActionsSubTab: String, CaseIterable, Hashable {
    case actions = "Actions"
    case store = "Store"
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the detail area. Matches the grouped-form content
    /// cap (600pt on macOS 15+), so Actions/Appearance render at the same
    /// width as the form-based tabs instead of stretching with the window.
    private static let detailContentMaxWidth: CGFloat = 600

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    @State private var selectedTab: PreferenceTab
    @State private var aiSubTab: AISubTab = .configure
    @State private var actionsSubTab: ActionsSubTab = .actions
    @State private var activeSheet: PreferencesSheet?
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

                    if selectedTab == .ai {
                        Picker("", selection: $aiSubTab) {
                            Text("Configure").tag(AISubTab.configure)
                            Text("Actions").tag(AISubTab.actions)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    } else if selectedTab == .actions {
                        Picker("", selection: $actionsSubTab) {
                            Text("Actions").tag(ActionsSubTab.actions)
                            Text("Store").tag(ActionsSubTab.store)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                .frame(maxWidth: Self.detailContentMaxWidth)
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
                        switch actionsSubTab {
                        case .actions:
                            ActionsTab(
                                disabledActionIDs: $disabledActionIDs,
                                disabledPackages: $disabledPackages,
                                onOpenAI: {
                                    aiSubTab = .configure
                                    selectedTab = .ai
                                }
                            )
                        case .store:
                            ExtensionStoreView()
                        }
                    case .ai:
                        AITab(selectedSubTab: $aiSubTab)
                    case .appRules: 
                        AppRulesTab()
                    case .about: 
                        AboutTab()
                    }
                }
                .frame(maxWidth: Self.detailContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                // General and Appearance grouped forms run edge-to-edge to the window bottom; other tabs keep breathing room.
                .padding(.bottom, (selectedTab == .general || selectedTab == .appearance) ? 0 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 760, idealWidth: 760, minHeight: 520, idealHeight: 620)
        .onAppear {
            loadDisabledState()
            Task {
                _ = try? await ExtensionsAPIClient.shared.fetchExtensions()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .actions {
                Task {
                    _ = try? await ExtensionsAPIClient.shared.fetchExtensions()
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
                EditActionSheet(action: action, configurationRequest: request)
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
