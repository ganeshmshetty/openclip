import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
public struct PreferencesView: View {
    @AppStorage(Constants.startAtLoginKey) private var startAtLogin: Bool = false
    @AppStorage(Constants.popupStyleKey) private var popupStyle: String = "modern"
    @AppStorage("popupTheme") private var theme: String = "glass"
    @AppStorage(Constants.popupSizeKey) private var popupSize: String = "medium"
    
    @State private var disabledActionIDs: Set<String> = []
    @State private var selectedTab = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)
            
            AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(1)
            
            ActionsTab(disabledActionIDs: $disabledActionIDs)
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
                .tag(2)
            
            AppRulesTab()
                .tabItem {
                    Label("App Rules", systemImage: "macwindow.badge.gearshape")
                }
                .tag(3)
            
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(4)
        }
        .frame(width: 580, height: 460)
        .padding(12)
        .onAppear {
            loadDisabledActionIDs()
        }
        .onChange(of: disabledActionIDs) { _, _ in
            saveDisabledActionIDs()
        }
    }
    
    private func loadDisabledActionIDs() {
        if let array = UserDefaults.standard.stringArray(forKey: Constants.disabledActionIDsKey) {
            disabledActionIDs = Set(array)
        }
    }
    
    private func saveDisabledActionIDs() {
        UserDefaults.standard.set(Array(disabledActionIDs), forKey: Constants.disabledActionIDsKey)
    }
}

@MainActor
struct GeneralTab: View {
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @State private var isAXTrusted: Bool = AXIsProcessTrustedWithOptions(nil)
    
    var body: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Trigger Popup")
                        .font(.body)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
            }
            
            Section("Startup") {
                Toggle("Start OpenClip at Login", isOn: $launchManager.isEnabled)
                    .toggleStyle(.checkbox)
            }
            
            Section("Permissions") {
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
                        Text(String(text.prefix(1))) // Fallback
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
