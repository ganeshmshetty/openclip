import SwiftUI
import Core

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
            GeneralTab(startAtLogin: $startAtLogin)
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
            
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(width: 540, height: 420)
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
    @Binding var startAtLogin: Bool
    @State private var isAXTrusted: Bool = AXIsProcessTrusted()
    
    var body: some View {
        Form {
            Section(header: Text("Startup & Menu Bar").font(.headline)) {
                Toggle("Start OpenClip at Login", isOn: $startAtLogin)
                    .help("Automatically launch OpenClip when you log into your Mac.")
            }
            
            Divider().padding(.vertical, 8)
            
            Section(header: Text("System Permissions").font(.headline)) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Access")
                            .font(.body).bold()
                        Text(isAXTrusted ? "OpenClip has permission to detect text selection." : "OpenClip needs Accessibility access to work.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isAXTrusted ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(isAXTrusted ? "Granted" : "Required")
                            .font(.subheadline)
                            .foregroundColor(isAXTrusted ? .green : .orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    
                    Button(action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("Open Settings")
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            isAXTrusted = AXIsProcessTrusted()
        }
    }
}

@MainActor
struct AppearanceTab: View {
    @Binding var popupStyle: String
    @Binding var theme: String
    @Binding var popupSize: String
    
    var body: some View {
        VStack(spacing: 20) {
            // Live Preview Card
            VStack(spacing: 8) {
                Text("Live Popup Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Image(systemName: "doc.on.doc").font(.system(size: 16))
                    Image(systemName: "scissors").font(.system(size: 16))
                    Image(systemName: "doc.on.clipboard").font(.system(size: 16))
                    Image(systemName: "magnifyingglass").font(.system(size: 16))
                    Image(systemName: "globe").font(.system(size: 16))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(previewBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            
            Form {
                Picker("Theme Style", selection: $theme) {
                    Text("Modern Glass (.ultraThinMaterial)").tag("glass")
                    Text("OLED Dark").tag("dark")
                    Text("Translucent Light").tag("light")
                }
                .pickerStyle(.segmented)
                
                Picker("Popup Size", selection: $popupSize) {
                    Text("Compact").tag("small")
                    Text("Standard").tag("medium")
                    Text("Large").tag("large")
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(20)
    }
    
    @ViewBuilder
    private var previewBackground: some View {
        switch theme {
        case "dark":
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
        case "light":
            Color.white.opacity(0.95)
        default:
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
        }
    }
}

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @State private var showingCustomURLAlert = false
    @State private var customTitle = ""
    @State private var customURL = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                Section(header: Text("Built-in & Registered Actions").font(.subheadline).bold()) {
                    ForEach(ActionRegistry.shared.actions, id: \.id) { action in
                        let isEnabled = Binding<Bool>(
                            get: { !disabledActionIDs.contains(action.id) },
                            set: { enabled in
                                if enabled {
                                    disabledActionIDs.remove(action.id)
                                } else {
                                    disabledActionIDs.insert(action.id)
                                }
                            }
                        )
                        
                        Toggle(isOn: isEnabled) {
                            HStack(spacing: 10) {
                                switch action.icon {
                                case .symbol(let name):
                                    Image(systemName: name)
                                        .frame(width: 20)
                                case .url, .local:
                                    Image(systemName: "sparkles")
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
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            
            HStack {
                Button(action: {
                    showingCustomURLAlert = true
                }, label: {
                    Label("Add Custom URL Search Action", systemImage: "plus.circle")
                })
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .padding(12)
        .sheet(isPresented: $showingCustomURLAlert) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Custom Search Action").font(.headline)
                
                TextField("Title (e.g. DuckDuckGo)", text: $customTitle)
                TextField("URL Template (use {text} for query)", text: $customURL)
                
                HStack {
                    Spacer()
                    Button(action: { showingCustomURLAlert = false }) {
                        Text("Cancel")
                    }
                    Button(action: {
                        if !customTitle.isEmpty && !customURL.isEmpty {
                            let newAction = URLTemplateAction(
                                id: "com.custom.search.\(UUID().uuidString.prefix(6))",
                                title: customTitle,
                                icon: .symbol("magnifyingglass"),
                                urlTemplate: customURL
                            )
                            ActionRegistry.shared.register(action: newAction)
                            customTitle = ""
                            customURL = ""
                            showingCustomURLAlert = false
                        }
                    }) {
                        Text("Add Action")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 400)
        }
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
