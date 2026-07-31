import SwiftUI
import Core

@MainActor
public struct PreferencesView: View {
    @AppStorage(Constants.startAtLoginKey) private var startAtLogin: Bool = false
    @AppStorage(Constants.popupStyleKey) private var popupStyle: String = "modern"
    @AppStorage(Constants.themeKey) private var theme: String = "system"
    @AppStorage(Constants.popupSizeKey) private var popupSize: String = "medium"
    
    @State private var disabledActionIDs: Set<String> = []

    public init() {}

    public var body: some View {
        TabView {
            GeneralTab(startAtLogin: $startAtLogin)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
            
            ActionsTab(disabledActionIDs: $disabledActionIDs)
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
        }
        .frame(width: 500, height: 400)
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
    
    var body: some View {
        Form {
            Toggle("Start at Login", isOn: $startAtLogin)
        }
        .padding()
    }
}

@MainActor
struct AppearanceTab: View {
    @Binding var popupStyle: String
    @Binding var theme: String
    @Binding var popupSize: String
    
    var body: some View {
        Form {
            Picker("Popup Style", selection: $popupStyle) {
                Text("Classic iOS Bubble").tag("classic")
                Text("Modern macOS Glass").tag("modern")
            }
            Picker("Theme", selection: $theme) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            Picker("Size", selection: $popupSize) {
                Text("Small").tag("small")
                Text("Medium").tag("medium")
                Text("Large").tag("large")
            }
        }
        .padding()
    }
}

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    
    var body: some View {
        List {
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
                    HStack {
                        switch action.icon {
                        case .symbol(let name):
                            Image(systemName: name)
                        case .url, .local:
                            Image(systemName: "circle")
                        }
                        Text(action.title)
                    }
                }
            }
        }
    }
}
