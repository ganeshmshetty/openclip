import SwiftUI
import AppKit
import Core

@MainActor
public struct AppRulesTab: View {
    @ObservedObject private var ruleEngine = RuleEngine.shared
    @State private var showingAddAppPopover = false
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Customize how OpenClip behaves in specific applications.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            List {
                if ruleEngine.userRules.isEmpty {
                    Text("No custom app rules. Click '+' to add one.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(ruleEngine.userRules) { rule in
                        AppRuleRowView(rule: rule) { updatedRule in
                            RuleEngine.shared.addOrUpdateRule(updatedRule)
                        } onDelete: {
                            RuleEngine.shared.removeRule(id: rule.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 250)
            
            HStack {
                Button(action: {
                    showingAddAppPopover = true
                }, label: {
                    Label("Add App", systemImage: "plus.circle")
                })
                .popover(isPresented: $showingAddAppPopover, arrowEdge: .bottom) {
                    RunningAppsPicker { app in
                        let newRule = AppRule(bundleIdentifiers: [app.bundleIdentifier ?? ""])
                        RuleEngine.shared.addOrUpdateRule(newRule)
                        showingAddAppPopover = false
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await RuleEngine.shared.loadRules(from: Constants.rulesFileURL)
                    }
                }, label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                })
                .help("Reload rules from ~/.openclip/rules.json")
            }
            .padding(.horizontal, 10)
        }
        .padding(12)
    }
}

@MainActor
private struct AppRuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onDelete: () -> Void
    
    private var bundleID: String {
        rule.bundleIdentifiers.first ?? "Unknown App"
    }
    
    // Derived bindings for toggles
    private var enableOpenClip: Binding<Bool> {
        Binding(
            get: { !(rule.denyProbe == true) },
            set: { onUpdate(updateRule(denyProbe: !$0)) }
        )
    }
    
    private var allowFormatting: Binding<Bool> {
        Binding(
            get: { !(rule.denyFormatting == true) },
            set: { onUpdate(updateRule(denyFormatting: !$0)) }
        )
    }
    
    private var forceClipboard: Binding<Bool> {
        Binding(
            get: { rule.grabPasteboard == true },
            set: { onUpdate(updateRule(grabPasteboard: $0)) }
        )
    }
    
    private func updateRule(denyProbe: Bool? = nil, denyFormatting: Bool? = nil, grabPasteboard: Bool? = nil) -> AppRule {
        let copy = rule
        if let val = denyProbe { 
            // If we deny probe, we also deny preprobe for complete disablement
            let newRule = AppRule(bundleIdentifiers: rule.bundleIdentifiers, denyFormatting: rule.denyFormatting, denyProbe: val ? true : nil, denyPreprobe: val ? true : nil, grabPasteboard: rule.grabPasteboard, grabKeyboard: rule.grabKeyboard, browserAddressBar: rule.browserAddressBar, assumePaste: rule.assumePaste, lenientSelect: rule.lenientSelect)
            return newRule
        }
        if let val = denyFormatting {
            let newRule = AppRule(bundleIdentifiers: rule.bundleIdentifiers, denyFormatting: val ? true : nil, denyProbe: rule.denyProbe, denyPreprobe: rule.denyPreprobe, grabPasteboard: rule.grabPasteboard, grabKeyboard: rule.grabKeyboard, browserAddressBar: rule.browserAddressBar, assumePaste: rule.assumePaste, lenientSelect: rule.lenientSelect)
            return newRule
        }
        if let val = grabPasteboard {
            let newRule = AppRule(bundleIdentifiers: rule.bundleIdentifiers, denyFormatting: rule.denyFormatting, denyProbe: rule.denyProbe, denyPreprobe: rule.denyPreprobe, grabPasteboard: val ? true : nil, grabKeyboard: rule.grabKeyboard, browserAddressBar: rule.browserAddressBar, assumePaste: rule.assumePaste, lenientSelect: rule.lenientSelect)
            return newRule
        }
        return copy
    }
    
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable OpenClip in this app", isOn: enableOpenClip)
                    .help("If disabled, OpenClip will ignore all text selections in this app.")
                
                Toggle("Show Formatting Actions", isOn: allowFormatting)
                    .help("If disabled, actions like Bold or Markdown formatting are hidden. Useful for code editors.")
                
                Toggle("Force Clipboard Copy (Cmd+C)", isOn: forceClipboard)
                    .help("Enable this for non-native apps (like Electron or Java) that do not support standard text accessibility.")
            }
            .padding(.leading, 24)
            .padding(.vertical, 6)
        } label: {
            HStack(spacing: 8) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                       let bundle = Bundle(url: appURL),
                       let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                        Text(appName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(bundleID)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(bundleID)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Remove Rule")
            }
            .padding(.vertical, 4)
        }
    }
}

@MainActor
private struct RunningAppsPicker: View {
    let onSelect: (NSRunningApplication) -> Void
    @State private var searchText = ""
    
    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != "com.openclip.OpenClip" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    var filteredApps: [NSRunningApplication] {
        if searchText.isEmpty { return runningApps }
        return runningApps.filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search running apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            
            Divider()
            
            List(filteredApps, id: \.bundleIdentifier) { app in
                Button {
                    onSelect(app)
                } label: {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }
                        Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 350)
    }
}
