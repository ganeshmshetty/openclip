import SwiftUI
import Core
import KeyboardShortcuts

enum PreferenceTab: String, CaseIterable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case actions = "Actions"
    case appRules = "App Rules"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .actions: return "bolt.fill"
        case .appRules: return "shield"
        case .about: return "info.circle"
        }
    }
}

@MainActor
public struct PreferencesView: View {
    @AppStorage(Constants.startAtLoginKey) private var startAtLogin: Bool = false
    @AppStorage(Constants.popupStyleKey) private var popupStyle: String = "modern"
    @AppStorage("popupTheme") private var theme: String = "glass"
    @AppStorage(Constants.popupSizeKey) private var popupSize: String = "medium"
    
    @State private var disabledActionIDs: Set<String> = []
    @State private var selectedTab: PreferenceTab = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Seamless Sidebar
            VStack(alignment: .leading, spacing: 4) {
                // Top spacing below window traffic light buttons (close/minimize/expand)
                Spacer()
                    .frame(height: 14)
                
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
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Help Center")
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/openclip-app/openclip") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        GitHubIconShape()
                            .fill(Color.secondary)
                            .frame(width: 15, height: 15)
                    }
                    .buttonStyle(.plain)
                    .help("GitHub Repository")
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 200)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
                .opacity(0.3)
            
            // Detail Area
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 20, weight: .bold))
                        .padding(.top, 0)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    Spacer()
                }
                
                Group {
                    switch selectedTab {
                    case .general: 
                        GeneralTab()
                    case .appearance: 
                        AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                    case .actions: 
                        ActionsTab(disabledActionIDs: $disabledActionIDs)
                    case .appRules: 
                        AppRulesTab()
                    case .about: 
                        AboutTab()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.14))
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { loadDisabledActionIDs() }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledActionIDs() }
    }
    
    private func loadDisabledActionIDs() {
        if let array = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey) {
            var set = Set(array)
            if !UserDefaults.standard.bool(forKey: "action.transform.enabled") {
                set.insert("builtin.transform")
            }
            disabledActionIDs = set
        } else {
            disabledActionIDs = ["builtin.transform"]
        }
    }
    
    private func saveDisabledActionIDs() {
        UserDefaults.standard.set(Array(disabledActionIDs), forKey: Constants.disabledActionIDsKey)
        if !disabledActionIDs.contains("builtin.transform") {
            UserDefaults.standard.set(true, forKey: "action.transform.enabled")
        } else {
            UserDefaults.standard.set(false, forKey: "action.transform.enabled")
        }
    }
}

@MainActor
struct GeneralTab: View {
    @AppStorage(Constants.isAppEnabledKey) private var isAppEnabled: Bool = true
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @State private var isAXTrusted: Bool = AXIsProcessTrustedWithOptions(nil)
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isAppEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable OpenClip")
                            .font(.body)
                            .fontWeight(.medium)
                        Text(isAppEnabled ? "OpenClip is active and monitoring text selection" : "OpenClip is paused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isAppEnabled) { _, newValue in
                    NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                }
                
                HStack {
                    Text("Trigger Popup Shortcut")
                        .font(.body)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
                
                Toggle("Start OpenClip at Login", isOn: $launchManager.isEnabled)
                    .toggleStyle(.checkbox)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text(isAXTrusted ? "Active permission for text selection" : "Required to detect text selection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isAXTrusted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isAXTrusted ? "Granted" : "Required")
                            .font(.caption)
                            .foregroundColor(isAXTrusted ? .green : .orange)
                        
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
        .onAppear {
            isAXTrusted = AXIsProcessTrustedWithOptions(nil)
        }
    }
}

@MainActor
struct AppearanceTab: View {
    @Binding var popupStyle: String
    @Binding var theme: String
    @Binding var popupSize: String
    
    private var mockContext: ActionContext {
        let app = NSRunningApplication.current
        let context = SelectionContext(
            text: "OpenClip Preview",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }
    
    @ObservedObject private var coordinator = ActionCoordinator.shared
    
    private var mockActions: [any Action] {
        let available = coordinator.resolveActions(for: mockContext)
        // Show up to 5 actions in the preview to look clean
        return Array(available.prefix(5))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Live Preview Card
            VStack(spacing: 12) {
                Text("Live Popup Preview")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                PopupView(actions: mockActions, context: mockContext) { _ in }
                    .scaleEffect(1.1)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            Form {
                Picker("Theme Style", selection: $theme) {
                    Text("Glass").tag("glass")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }
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
        VStack(alignment: .leading, spacing: 10) {
            List {
                Section(header: Text("Built-in & Registered Actions").font(.subheadline).bold()) {
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
        }
        .padding(12)
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
    }
    
    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Extension to Install"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip, .shellScript, .pythonScript, .plainText]
        
        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                Task {
                    do {
                        _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    } catch {
                        print("Failed to install extension: \(error)")
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
    
    private var configurableAction: (any ConfigurableAction)? {
        action as? any ConfigurableAction
    }
    
    private var displayIcon: ActionIcon {
        if let configurable = configurableAction {
            return .symbol(configurable.preferenceIconName)
        }
        return action.icon
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: isEnabled) {
                HStack(spacing: 10) {
                    switch displayIcon {
                    case .symbol(let name):
                        Image(systemName: name)
                            .frame(width: 20)
                    case .url, .local:
                        Image(systemName: "sparkles")
                            .frame(width: 20)
                    case .text(let text):
                        Text(text)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 20)
                    }
                    Text(action.title)
                        .font(.body)
                    Spacer()
                    if action is ScriptAction {
                        Text("Script")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundColor(.blue)
                    } else if action is URLTemplateAction {
                        Text("URL Template")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                            .foregroundColor(.purple)
                    } else if let customAction = action as? CustomAction {
                        CustomActionBadge(type: customAction.type)
                    }
                }
            }
            
            if let configurable = configurableAction {
                Button(action: {
                    showingConfigSheet = true
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Configure Action")
                .sheet(isPresented: $showingConfigSheet) {
                    ActionConfigSheet(configurationViewID: configurable.configurationViewID)
                }
            }
            
            if let customAction = action as? CustomAction {
                Button(action: {
                    CustomActionManager.shared.delete(customActionID: customAction.id)
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete Custom Action")
            } else if action is ScriptAction || action is URLTemplateAction {
                Button(action: {
                    Task {
                        try? await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                    }
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Uninstall Extension")
            }
        }
    }
}

@MainActor
struct TransformGroupRowView: View {
    let groupAction: any Action
    @Binding var disabledActionIDs: Set<String>
    @State private var isExpanded = false
    
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
                            Toggle(tCase.displayName, isOn: isSubActionEnabled(tCase))
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .padding(.leading, 24)
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 10) {
                Toggle(isOn: isGroupEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat")
                            .frame(width: 20)
                        Text(groupAction.title)
                            .font(.body)
                        Spacer()
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

struct CustomActionBadge: View {
    let type: CustomActionType
    
    var body: some View {
        let (text, color): (String, Color) = {
            switch type {
            case .webSearch: return ("Web Search", .purple)
            case .textSnippet: return ("Snippet", .green)
            case .shellScript: return ("Script", .blue)
            }
        }()
        
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundColor(color)
    }
}

@MainActor
struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 4) {
                Text("OpenClip")
                    .font(.title).bold()
                Text("Version 1.0.0")
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
