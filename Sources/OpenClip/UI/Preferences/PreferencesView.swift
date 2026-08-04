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
    case extensions = "Extensions"
    case ai = "AI"
    case appRules = "App Rules"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .actions: return "bolt.horizontal.fill"
        case .extensions: return "puzzlepiece.extension.fill"
        case .ai: return "sparkles"
        case .appRules: return "shield.checkerboard"
        case .about: return "info.circle.fill"
        }
    }
}

@MainActor
public struct PreferencesView: View {
    /// Shared max content width for the detail area. Matches the grouped-form content
    /// cap (600pt on macOS 15+), so Actions/Appearance/Extensions render at the same
    /// width as the form-based tabs instead of stretching with the window.
    private static let detailContentMaxWidth: CGFloat = 600

    @AppStorage(Constants.startAtLoginKey) private var startAtLogin: Bool = false
    
    @State private var disabledActionIDs: Set<String> = []
    @State private var selectedTab: PreferenceTab = .general
    @State private var aiSubTab: AISubTab = .configure
    @State private var extensionsSubTab: ExtensionSubTab = .store
    @State private var configuringAction: ConfigurationSheetItem?
    @ObservedObject private var configurationCoordinator = ActionConfigurationCoordinator.shared

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
                        if let url = URL(string: "https://openclip.app/help") {
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
                        GitHubIconShape()
                            .fill(Color.primary)
                            .frame(width: 17, height: 17)
                            .contentShape(Rectangle())
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
                    } else if selectedTab == .extensions {
                        Picker("", selection: $extensionsSubTab) {
                            Text("Store").tag(ExtensionSubTab.store)
                            Text("Installed (\(installedExtensionCount))").tag(ExtensionSubTab.installed)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 180)
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
                        ActionsTab(disabledActionIDs: $disabledActionIDs)
                    case .extensions:
                        ExtensionsStoreView(selectedSubTab: $extensionsSubTab)
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
        .onAppear { loadDisabledActionIDs() }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledActionIDs() }
        .onChange(of: configurationCoordinator.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            configurationCoordinator.pendingRequest = nil
            guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == request.actionID }) else { return }
            configuringAction = ConfigurationSheetItem(action: action)
        }
        .sheet(item: $configuringAction) { item in
            EditActionSheet(action: item.action)
        }
    }
    
    private func loadDisabledActionIDs() {
        var set = DefaultSettingsStore.shared.get(.disabledActionIDs)
        if !DefaultSettingsStore.shared.get(.isTransformGroupEnabled) {
            set.insert("builtin.transform")
        }
        disabledActionIDs = set
    }
    
    private func saveDisabledActionIDs() {
        DefaultSettingsStore.shared.set(.disabledActionIDs, value: disabledActionIDs)
        let transformEnabled = !disabledActionIDs.contains("builtin.transform")
        DefaultSettingsStore.shared.set(.isTransformGroupEnabled, value: transformEnabled)
    }

}

/// Identifiable wrapper so a config sheet can be driven by `.sheet(item:)` with any `Action`.
private struct ConfigurationSheetItem: Identifiable {
    let action: any Action
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
    @State private var showingAddActionSheet = false
    @ObservedObject private var coordinator = ActionCoordinator.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                Section {
                    ForEach(coordinator.actions.filter { !$0.id.hasPrefix("builtin.transform.") }, id: \.id) { action in
                        if action.id == "builtin.transform" {
                            TransformGroupRowView(groupAction: action, disabledActionIDs: $disabledActionIDs)
                        } else {
                            ActionRowView(action: action, disabledActionIDs: $disabledActionIDs)
                        }
                    }
                    .onMove { source, destination in
                        coordinator.moveActions(from: source, to: destination)
                    }
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
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    
    var isEnabled: Binding<Bool> {
        Binding<Bool>(
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
        ActionPresentation.shared.presented(action, surface: .table)
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
                case .custom:
                    Button(action: {
                        CustomActionManager.shared.delete(customActionID: action.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .help("Delete Custom Action")
                    .accessibilityLabel("Delete Custom Action")
                case .extensionPkg:
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
                case .builtin:
                    EmptyView()
                }

                // Enable/Disable Switch
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Enable \(action.displayTitle)")
                
                // Edit / Configure Button
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
        .padding(.vertical, 4)
    }
}


@MainActor
struct TransformGroupRowView: View {
    let groupAction: any Action
    @Binding var disabledActionIDs: Set<String>
    @State private var isExpanded = false
    @State private var showingConfigSheet = false
    
    private var isGroupEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { !disabledActionIDs.contains(groupAction.id) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.remove(groupAction.id)
                } else {
                    disabledActionIDs.insert(groupAction.id)
                }
            }
        )
    }
    
    private func isSubActionEnabled(_ tCase: TransformCase) -> Binding<Bool> {
        let actionID = "builtin.transform.\(tCase.rawValue)"
        return Binding<Bool>(
            get: { !disabledActionIDs.contains(actionID) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.remove(actionID)
                    disabledActionIDs.remove(groupAction.id)
                } else {
                    disabledActionIDs.insert(actionID)
                }
            }
        )
    }
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(TransformCategory.allCases, id: \.rawValue) { category in
                    let catCases = TransformCase.allCases.filter { $0.category == category }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.rawValue)
                            .font(.caption)
                            .bold()
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        ForEach(catCases) { tCase in
                            HStack {
                                Text(tCase.displayName)
                                    .font(.system(size: 12))
                                Spacer()
                                Toggle("", isOn: isSubActionEnabled(tCase))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .accessibilityLabel("Enable \(tCase.displayName)")
                            }
                        }
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.vertical, 4)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Icon Column
                ZStack {
                    if case .symbol(let name) = groupAction.displayIcon {
                        AnyIconView(iconId: name)
                            .frame(width: 14, height: 14)
                    } else if case .text(let txt) = groupAction.displayIcon {
                        Text(txt)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: "textformat")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                }
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(6)
                
                // Title Column
                Text(groupAction.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                // Right-aligned controls (Toggle | Gear)
                HStack(alignment: .center, spacing: 12) {
                    // Enable/Disable Switch
                    Toggle("", isOn: isGroupEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Enable \(groupAction.displayTitle)")
                    
                    // Edit / Configure Button
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
                        EditActionSheet(action: groupAction)
                    }
                }
            }
            .padding(.vertical, 4)
        }
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

struct GitHubIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24.0
        let offsetX = (rect.width - 24.0 * scale) / 2.0
        let offsetY = (rect.height - 24.0 * scale) / 2.0
        
        var path = Path()
        path.move(to: CGPoint(x: 12 * scale + offsetX, y: 0 * scale + offsetY))
        
        path.addCurve(
            to: CGPoint(x: 0 * scale + offsetX, y: 12 * scale + offsetY),
            control1: CGPoint(x: 5.37 * scale + offsetX, y: 0 * scale + offsetY),
            control2: CGPoint(x: 0 * scale + offsetX, y: 5.37 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 8.205 * scale + offsetX, y: 23.385 * scale + offsetY),
            control1: CGPoint(x: 0 * scale + offsetX, y: 17.31 * scale + offsetY),
            control2: CGPoint(x: 3.435 * scale + offsetX, y: 21.795 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 9.03 * scale + offsetX, y: 22.815 * scale + offsetY),
            control1: CGPoint(x: 8.805 * scale + offsetX, y: 23.49 * scale + offsetY),
            control2: CGPoint(x: 9.03 * scale + offsetX, y: 23.13 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 9.015 * scale + offsetX, y: 20.58 * scale + offsetY),
            control1: CGPoint(x: 9.03 * scale + offsetX, y: 22.53 * scale + offsetY),
            control2: CGPoint(x: 9.015 * scale + offsetX, y: 21.585 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 4.98 * scale + offsetX, y: 19.17 * scale + offsetY),
            control1: CGPoint(x: 6.0 * scale + offsetX, y: 21.135 * scale + offsetY),
            control2: CGPoint(x: 5.22 * scale + offsetX, y: 19.845 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 3.75 * scale + offsetX, y: 17.475 * scale + offsetY),
            control1: CGPoint(x: 4.845 * scale + offsetX, y: 18.825 * scale + offsetY),
            control2: CGPoint(x: 4.26 * scale + offsetX, y: 17.76 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 3.735 * scale + offsetX, y: 16.68 * scale + offsetY),
            control1: CGPoint(x: 3.33 * scale + offsetX, y: 17.25 * scale + offsetY),
            control2: CGPoint(x: 2.73 * scale + offsetX, y: 16.695 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 5.58 * scale + offsetX, y: 17.91 * scale + offsetY),
            control1: CGPoint(x: 4.68 * scale + offsetX, y: 16.665 * scale + offsetY),
            control2: CGPoint(x: 5.355 * scale + offsetX, y: 17.55 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 9.075 * scale + offsetX, y: 18.9 * scale + offsetY),
            control1: CGPoint(x: 6.66 * scale + offsetX, y: 19.725 * scale + offsetY),
            control2: CGPoint(x: 8.385 * scale + offsetX, y: 19.215 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 9.84 * scale + offsetX, y: 17.295 * scale + offsetY),
            control1: CGPoint(x: 9.18 * scale + offsetX, y: 18.12 * scale + offsetY),
            control2: CGPoint(x: 9.495 * scale + offsetX, y: 17.595 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 4.38 * scale + offsetX, y: 11.37 * scale + offsetY),
            control1: CGPoint(x: 7.17 * scale + offsetX, y: 16.995 * scale + offsetY),
            control2: CGPoint(x: 4.38 * scale + offsetX, y: 15.96 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 5.61 * scale + offsetX, y: 8.145 * scale + offsetY),
            control1: CGPoint(x: 4.38 * scale + offsetX, y: 10.065 * scale + offsetY),
            control2: CGPoint(x: 4.845 * scale + offsetX, y: 8.985 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 5.73 * scale + offsetX, y: 4.965 * scale + offsetY),
            control1: CGPoint(x: 5.49 * scale + offsetX, y: 7.845 * scale + offsetY),
            control2: CGPoint(x: 5.07 * scale + offsetX, y: 6.615 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 9.03 * scale + offsetX, y: 6.195 * scale + offsetY),
            control1: CGPoint(x: 5.73 * scale + offsetX, y: 4.965 * scale + offsetY),
            control2: CGPoint(x: 6.735 * scale + offsetX, y: 4.65 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 12 * scale + offsetX, y: 5.79 * scale + offsetY),
            control1: CGPoint(x: 9.99 * scale + offsetX, y: 5.925 * scale + offsetY),
            control2: CGPoint(x: 11.01 * scale + offsetX, y: 5.79 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 14.97 * scale + offsetX, y: 6.195 * scale + offsetY),
            control1: CGPoint(x: 12.99 * scale + offsetX, y: 5.79 * scale + offsetY),
            control2: CGPoint(x: 14.01 * scale + offsetX, y: 5.925 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 18.27 * scale + offsetX, y: 4.965 * scale + offsetY),
            control1: CGPoint(x: 17.265 * scale + offsetX, y: 4.635 * scale + offsetY),
            control2: CGPoint(x: 18.27 * scale + offsetX, y: 4.965 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 18.39 * scale + offsetX, y: 8.145 * scale + offsetY),
            control1: CGPoint(x: 18.93 * scale + offsetX, y: 6.615 * scale + offsetY),
            control2: CGPoint(x: 18.51 * scale + offsetX, y: 7.845 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 19.62 * scale + offsetX, y: 11.37 * scale + offsetY),
            control1: CGPoint(x: 19.155 * scale + offsetX, y: 8.985 * scale + offsetY),
            control2: CGPoint(x: 19.62 * scale + offsetX, y: 10.05 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 14.145 * scale + offsetX, y: 17.295 * scale + offsetY),
            control1: CGPoint(x: 19.62 * scale + offsetX, y: 15.975 * scale + offsetY),
            control2: CGPoint(x: 16.815 * scale + offsetX, y: 16.995 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 14.955 * scale + offsetX, y: 19.515 * scale + offsetY),
            control1: CGPoint(x: 14.58 * scale + offsetX, y: 17.67 * scale + offsetY),
            control2: CGPoint(x: 14.955 * scale + offsetX, y: 18.39 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 14.94 * scale + offsetX, y: 22.815 * scale + offsetY),
            control1: CGPoint(x: 14.955 * scale + offsetX, y: 21.12 * scale + offsetY),
            control2: CGPoint(x: 14.94 * scale + offsetX, y: 22.41 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 15.765 * scale + offsetX, y: 23.385 * scale + offsetY),
            control1: CGPoint(x: 14.94 * scale + offsetX, y: 23.13 * scale + offsetY),
            control2: CGPoint(x: 15.165 * scale + offsetX, y: 23.49 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 24 * scale + offsetX, y: 12 * scale + offsetY),
            control1: CGPoint(x: 20.565 * scale + offsetX, y: 21.795 * scale + offsetY),
            control2: CGPoint(x: 24 * scale + offsetX, y: 17.31 * scale + offsetY)
        )
        path.addCurve(
            to: CGPoint(x: 12 * scale + offsetX, y: 0 * scale + offsetY),
            control1: CGPoint(x: 24 * scale + offsetX, y: 5.37 * scale + offsetY),
            control2: CGPoint(x: 18.63 * scale + offsetX, y: 0 * scale + offsetY)
        )
        path.closeSubpath()
        return path
    }
}
