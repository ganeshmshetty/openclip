// PreferencesView.swift
// OpenClip
//
// Renders the primary multi-tab preferences window interface for OpenClip.
import SwiftUI
import Core
import KeyboardShortcuts

enum PreferenceTab: String, CaseIterable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case actions = "Actions"
    case ai = "AI"
    case appRules = "App Rules"
    case about = "About"
    
    var icon: String {
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

/// Sub-tab selector for the merged Actions tab (Actions | Store | Installed).
enum ActionsSubTab: String, CaseIterable, Hashable {
    case actions = "Actions"
    case store = "Store"
    case installed = "Installed"
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the detail area. Matches the grouped-form content
    /// cap (600pt on macOS 15+), so Actions/Appearance render at the same
    /// width as the form-based tabs instead of stretching with the window.
    private static let detailContentMaxWidth: CGFloat = 600

    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    @State private var selectedTab: PreferenceTab = .general
    @State private var aiSubTab: AISubTab = .configure
    @State private var actionsSubTab: ActionsSubTab = .actions
    @State private var configuringAction: ConfigurationSheetItem?
    @State private var trustReview: TrustReviewTarget? = nil

    private var installedExtensionCount: Int {
        ActionCoordinator.shared.actions.filter { ActionIdentity.isExtension($0) }.count
    }

    public init() {}

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
                            Text(tab.rawValue)
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
                }
                
                Spacer()
                
                // Bottom footer icons (Help and GitHub - NO TEXT)
                HStack(spacing: 14) {
                    Button(action: {
                        if let url = URL(string: "https://getopenclip.vercel.app/help") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Help Center")
                    .accessibilityLabel("Help Center")
                    
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
                    Text(selectedTab.rawValue)
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
                            Text("Installed (\(installedExtensionCount))").tag(ActionsSubTab.installed)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
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
                        case .installed:
                            InstalledExtensionsView()
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
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.all, edges: .top)
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 760, idealWidth: 760, minHeight: 520, idealHeight: 600)
        .onAppear { loadDisabledState() }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledState() }
        .onChange(of: disabledPackages) { _, _ in saveDisabledState() }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenActionConfiguration)) { notification in
            guard let request = notification.userInfo?["request"] as? ConfigurationRequest,
                  let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            configuringAction = ConfigurationSheetItem(action: action, request: request)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenTrustModel)) { notification in
            guard let packageID = notification.userInfo?["packageID"] as? String else { return }
            let reason = notification.userInfo?["reason"] as? ExtensionGateReason
            actionsSubTab = .installed
            trustReview = TrustReviewTarget(packageID: packageID, reason: reason)
        }
        .sheet(item: $configuringAction) { item in
            EditActionSheet(action: item.action, configurationRequest: item.request)
        }
        .sheet(item: $trustReview) { target in
            TrustModelView(model: TrustModelViewModel.load(packageID: target.packageID, reason: target.reason))
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

/// Identifiable wrapper so a config sheet can be driven by `.sheet(item:)` with any `Action`,
/// optionally carrying the `ConfigurationRequest` that opened it (reason banner + missing highlights).
private struct ConfigurationSheetItem: Identifiable {
    let action: any Action
    let request: ConfigurationRequest?
    var id: String { action.id }
}
