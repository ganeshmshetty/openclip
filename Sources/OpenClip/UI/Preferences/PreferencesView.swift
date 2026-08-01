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
        HStack(spacing: 0) {
            PreferencesSidebar(selectedTab: $selectedTab)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header Title
                Text(tabTitle(for: selectedTab))
                    .font(.system(size: 18, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch selectedTab {
                        case 0: GeneralTab()
                        case 1: AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                        case 2: ActionsTab(disabledActionIDs: $disabledActionIDs)
                        case 3: AppRulesTab()
                        case 4: AboutTab()
                        default: EmptyView()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 740, height: 520)
        .onAppear {
            loadDisabledActionIDs()
        }
        .onChange(of: disabledActionIDs) { _, _ in
            saveDisabledActionIDs()
        }
    }
    
    private func tabTitle(for tab: Int) -> String {
        switch tab {
        case 0: return "General"
        case 1: return "Appearance"
        case 2: return "Actions"
        case 3: return "App Rules"
        case 4: return "About OpenClip"
        default: return "Settings"
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

// MARK: - Sidebar & Group Utilities

@MainActor
struct PreferencesSidebar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(id: Int, title: String, icon: String)] = [
        (0, "General", "gearshape"),
        (1, "Appearance", "paintpalette"),
        (2, "Actions", "bolt.fill"),
        (3, "App Rules", "macwindow.badge.gearshape"),
        (4, "About", "info.circle")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tabs, id: \.id) { tab in
                Button {
                    selectedTab = tab.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(selectedTab == tab.id ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTab == tab.id ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Divider()
                .padding(.vertical, 6)
            
            // Icon-only Footer: Help (?) and GitHub
            HStack(spacing: 14) {
                Button {
                    if let url = URL(string: "https://github.com/ganesh/openclip#readme") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Help & Documentation")
                
                Button {
                    if let url = URL(string: "https://github.com/ganesh/openclip") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "code")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open GitHub Repository")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(12)
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
}

@MainActor
struct SettingsGroupCard<Content: View>: View {
    let title: String?
    let content: Content
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
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
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroupCard(title: "Live Popup Preview") {
                VStack {
                    PopupView(actions: mockActions, context: mockContext) { _ in }
                        .scaleEffect(1.05)
                        .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
            }
            
            SettingsGroupCard(title: "Theme & Aesthetics") {
                HStack {
                    Text("Popup Theme")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $theme) {
                        Text("Glass").tag("glass")
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
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
        VStack(spacing: 20) {
            SettingsGroupCard {
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    
                    VStack(spacing: 4) {
                        Text("OpenClip")
                            .font(.title2).bold()
                        Text("Version 1.0.0 (Native)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("The open-source text selection action tool for macOS.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
    }
}
