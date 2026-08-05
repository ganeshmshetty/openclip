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
        case .ai: return "sparkles"
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

    @AppStorage(Constants.startAtLoginKey) private var startAtLogin: Bool = false
    
    @State private var disabledActionIDs: Set<String> = []
    @State private var disabledPackages: Set<String> = []
    @State private var selectedTab: PreferenceTab = .general
    @State private var aiSubTab: AISubTab = .configure
    @State private var actionsSubTab: ActionsSubTab = .actions
    @State private var configuringAction: ConfigurationSheetItem?

    private var installedExtensionCount: Int {
        ActionCoordinator.shared.actions.filter { action in
            if case .extensionPkg = action.chrome.badge { return true }
            if case .extensionPkg = action.chrome.source { return true }
            return false
        }.count
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Seamless Sidebar
            VStack(alignment: .leading, spacing: 4) {
                // Top spacing so the window traffic lights (close/minimize/expand)
                // float seamlessly over the sidebar without covering the first tab item.
                // 23pt + the 7pt button padding aligns the first tab's text with the
                // detail header's 30pt top padding while clearing the traffic lights.
                Spacer()
                    .frame(height: 23)
                
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
                .padding(.top, 30)
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
        .glassSurface(.regular, cornerRadius: 0)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 640, idealHeight: 720)
        .onAppear { loadDisabledState() }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledState() }
        .onChange(of: disabledPackages) { _, _ in saveDisabledState() }
        .onReceive(NotificationCenter.default.publisher(for: .openClipOpenActionConfiguration)) { notification in
            guard let request = notification.userInfo?["request"] as? ConfigurationRequest,
                  let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            configuringAction = ConfigurationSheetItem(action: action, request: request)
        }
        .sheet(item: $configuringAction) { item in
            EditActionSheet(action: item.action, configurationRequest: item.request)
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

@MainActor
struct GeneralTab: View {
    @AppStorage(Constants.isAppEnabledKey) private var isAppEnabled: Bool = true
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("General Controls")) {
                // Row 1: Enable OpenClip
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "power")
                            .font(.system(size: 16))
                            .foregroundColor(isAppEnabled ? .accentColor : .secondary)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable OpenClip")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(isAppEnabled ? "Active & monitoring text selection" : "OpenClip is paused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $isAppEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Enable OpenClip")
                        .onChange(of: isAppEnabled) { _, newValue in
                            NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                        }
                }
                .padding(.vertical, 4)
                
                // Row 2: Trigger Shortcut
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trigger Popup Shortcut")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Global hotkey to manually trigger OpenClip HUD")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
                .padding(.vertical, 4)
                
                // Row 3: Start at Login
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start at Login")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Launch OpenClip automatically when logging in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $launchManager.isEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Start at Login")
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("System Permissions")) {
                // Row 4: Accessibility Access
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16))
                            .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility Access")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(permissionManager.isAccessibilityGranted ? "Active permission for text detection" : "Required to detect selected text in apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(permissionManager.isAccessibilityGranted ? "Granted" : "Required")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((permissionManager.isAccessibilityGranted ? Color.green : Color.orange).opacity(0.15))
                        )
                        
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }
}

@MainActor
struct AppearanceTab: View {
    var body: some View {
        VStack(spacing: 24) {
            PopupPreview()

            PopupThemeSelector()
                .padding(.horizontal, 10)

            Spacer()
        }
        .padding(24)
    }
}

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// Called by the AI Tools row's gear to open the AI tab. Wired in PreferencesView to switch
    /// `selectedTab` to `.ai` (and land on the Configure sub-tab where `isAIEnabled` lives).
    let onOpenAI: () -> Void
    @State private var showingAddActionSheet = false
    @ObservedObject private var coordinator = ActionCoordinator.shared
    
    /// Row model for the grouped actions list: multi-action extension packages get a package
    /// header row (with a whole-package toggle) before their actions; single-action packages and
    /// builtins stay flat.
    private enum ListRow: Identifiable {
        case packageHeader(packageID: String, title: String)
        case action(any Action)
        
        var id: String {
            switch self {
            case .packageHeader(let packageID, _): return "pkg.\(packageID)"
            case .action(let action): return action.id
            }
        }
    }
    
    private var packageActionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for action in coordinator.actions {
            if case .extensionPkg(let packageID) = action.chrome.source {
                counts[packageID, default: 0] += 1
            }
        }
        return counts
    }
    
    private var listRows: [ListRow] {
        var seenPackages: Set<String> = []
        var rows: [ListRow] = []
        for action in coordinator.actions {
            // AI presets never appear here — they're managed in the AI tab (and the palette).
            // The reorderable "AI Tools" launcher action (chrome.launchesAI) renders as a normal row.
            if case .ai = action.chrome.source {
                continue
            }
            if case .extensionPkg(let packageID) = action.chrome.source {
                if !seenPackages.contains(packageID) {
                    seenPackages.insert(packageID)
                    if packageActionCounts[packageID] ?? 0 >= 2 {
                        let title: String
                        if case .extensionPkg(let name) = action.chrome.badge {
                            title = name
                        } else {
                            title = packageID
                        }
                        rows.append(.packageHeader(packageID: packageID, title: title))
                    }
                }
                rows.append(.action(action))
            } else {
                rows.append(.action(action))
            }
        }
        return rows
    }
    
    /// Translates indices in the grouped row list (which contains inert package headers) back to
    /// `coordinator.actions` indices so reordering stays correct despite the inserted headers.
    private func moveRows(source: IndexSet, destination: Int) {
        let actionIndices: [(rowIndex: Int, actionIndex: Int)] = listRows.enumerated().compactMap { rowIndex, row in
            guard case .action(let action) = row else { return nil }
            guard let actionIndex = coordinator.actions.firstIndex(where: { $0.id == action.id }) else { return nil }
            return (rowIndex, actionIndex)
        }
        let actionIndexByRow = Dictionary(uniqueKeysWithValues: actionIndices.map { ($0.rowIndex, $0.actionIndex) })
        let actionSource = IndexSet(source.compactMap { actionIndexByRow[$0] })
        let actionDestination = actionIndices.prefix { $0.rowIndex < destination }.count
        coordinator.moveActions(from: actionSource, to: actionDestination)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                Section {
                    ForEach(listRows) { row in
                        switch row {
                        case .packageHeader(let packageID, let title):
                            PackageHeaderRowView(packageID: packageID, title: title, disabledPackages: $disabledPackages)
                        case .action(let action):
                            ActionRowView(action: action, disabledActionIDs: $disabledActionIDs, onOpenAI: onOpenAI)
                        }
                    }
                    .onMove(perform: moveRows)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack(spacing: 12) {
                Button(action: {
                    showingAddActionSheet = true
                }, label: {
                    Label("Add Custom Action", systemImage: "plus.circle")
                })
                
                Button(action: {
                    openInstallExtensionPanel()
                }, label: {
                    Label("Install Extension…", systemImage: "square.and.arrow.down")
                })
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
    }
    
    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Extension to Install"
        panel.message = "Choose a .openclipext folder, .zip archive, or script file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // Treat .openclipext packages as directories so they can be read
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    await MainActor.run {
                        // Post notification so any listening view refreshes its action list
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Extension Install Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
}

@MainActor
struct ActionRowView: View {
    let action: any Action
    @Binding var disabledActionIDs: Set<String>
    /// Opens the AI tab (AI Tools launcher rows); nil for rows without a nav gear.
    let onOpenAI: (() -> Void)?
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    init(action: any Action, disabledActionIDs: Binding<Set<String>>, onOpenAI: (() -> Void)? = nil) {
        self.action = action
        self._disabledActionIDs = disabledActionIDs
        self.onOpenAI = onOpenAI
    }

    /// AI preset rows share their toggle with the AI tab: enabling/disabling here (or there)
    /// writes the preset's `isEnabled`, the single source of truth. Never touches
    /// `disabledActionIDs`, which drives the bar via ActionRegistry.availableActions.
    private var isAI: Bool {
        if case .ai = action.chrome.source { return true }
        return false
    }

    /// The "AI Tools" bar launcher also shares its toggle with the AI tab — but with
    /// `isAIEnabled`, the single source of truth for the whole AI feature. Never touches
    /// `disabledActionIDs`.
    private var isAITools: Bool {
        action.chrome.launchesAI
    }

    var isEnabled: Binding<Bool> {
        if isAITools {
            return Binding<Bool>(
                get: { aiManager.isAIEnabled },
                set: { aiManager.isAIEnabled = $0 }
            )
        }
        if isAI {
            return Binding<Bool>(
                get: { aiManager.preset(forActionID: action.id)?.isEnabled ?? false },
                set: { enabled in
                    guard var preset = aiManager.preset(forActionID: action.id) else { return }
                    preset.isEnabled = enabled
                    aiManager.updatePreset(preset)
                }
            )
        }
        return Binding<Bool>(
            get: { !disabledActionIDs.contains(action.id) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.remove(action.id)
                } else {
                    disabledActionIDs.insert(action.id)
                }
            }
        )
    }
    
    @State private var showingConfigSheet = false
    
    private var presentationModel: ActionPresentationModel {
        ActionCustomizationManager.shared.presented(action, surface: .table)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon Column
            ZStack {
                ActionIconView(icon: presentationModel.icon, size: 14)
            }
            .frame(width: 28, height: 28)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            
            // Title Column
            Text(presentationModel.title)
                .font(.system(size: 13, weight: .medium))

            Spacer()
            
            // Right-aligned controls (Remove | Toggle | Gear)
            HStack(alignment: .center, spacing: 12) {
                // Delete / Uninstall Button (if applicable)
                switch action.chrome.source {
                case .custom, .extensionPkg:
                    // GUI-created custom actions live in manifest packages (source .extensionPkg),
                    // and snippet-sourced custom actions are standalone files — both uninstall by
                    // removing the package/folder that produced the action's id.
                    Button(action: {
                        Task {
                            try? await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .help("Uninstall Extension")
                    .accessibilityLabel("Uninstall Extension")
                case .builtin, .ai:
                    // AI preset rows are managed (and removed) in the AI tab, not here.
                    EmptyView()
                }

                // Enable/Disable Switch
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Enable \(action.displayTitle)")
                
                // Edit / Configure Button. AI Tools launcher rows get a gear that opens the AI tab
                // (where `isAIEnabled` lives); AI preset rows get none; everything else edits via sheet.
                if isAITools {
                    if let onOpenAI {
                        Button(action: onOpenAI) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 24, height: 24)
                        .help("Open AI settings")
                        .accessibilityLabel("Open AI settings")
                    }
                } else if !isAI {
                    Button(action: {
                        showingConfigSheet = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .help("Configure Action")
                    .accessibilityLabel("Configure Action")
                    .sheet(isPresented: $showingConfigSheet) {
                        EditActionSheet(action: action)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}


@MainActor
struct PackageHeaderRowView: View {
    let packageID: String
    let title: String
    @Binding var disabledPackages: Set<String>
    
    var isEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { !disabledPackages.contains(packageID) },
            set: { enabled in
                if enabled {
                    disabledPackages.remove(packageID)
                } else {
                    disabledPackages.insert(packageID)
                }
            }
        )
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 28, height: 28)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(title)")
        }
        .padding(.vertical, 4)
    }
}

@MainActor
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 4) {
                Text("OpenClip")
                    .font(.title).bold()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("The open-source text selection action tool for macOS.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding(20)
    }
}

