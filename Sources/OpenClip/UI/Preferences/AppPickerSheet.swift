import SwiftUI
import AppKit
import Core

@MainActor
public struct AppPickerSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var customBundleID = ""
    
    @StateObject private var scanner = InstalledAppsScanner()
    
    public init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }
    
    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != "com.openclip.OpenClip" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    private var filteredRunningApps: [NSRunningApplication] {
        if searchText.isEmpty { return runningApps }
        return runningApps.filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(searchText) || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(searchText) }
    }
    
    private var filteredInstalledApps: [InstalledAppInfo] {
        if searchText.isEmpty { return scanner.installedApps }
        return scanner.installedApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Running Apps").tag(0)
                Text("Installed Apps").tag(1)
                Text("Custom / Wildcard").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(12)
            
            Divider()
            
            if selectedTab == 2 {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter Bundle Identifier or Wildcard Pattern")
                            .font(.headline)
                        Text("Examples: com.apple.Terminal, com.jetbrains.*, *.vscode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("e.g. com.jetbrains.*", text: $customBundleID)
                        .textFieldStyle(.roundedBorder)
                    
                    Spacer()
                    
                    HStack {
                        Button("Cancel") { dismiss() }
                        Spacer()
                        Button("Add Rule") {
                            let trimmed = customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onSelect(trimmed)
                                dismiss()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(height: 320)
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search applications...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                
                Divider()
                
                if selectedTab == 0 {
                    List(filteredRunningApps, id: \.bundleIdentifier) { app in
                        Button {
                            if let bid = app.bundleIdentifier {
                                onSelect(bid)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                                        .font(.system(size: 13, weight: .medium))
                                    Text(app.bundleIdentifier ?? "")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Group {
                        if scanner.isLoading {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Scanning installed applications...").font(.caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List(filteredInstalledApps) { app in
                                Button {
                                    onSelect(app.bundleIdentifier)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                                .resizable()
                                                .frame(width: 24, height: 24)
                                        } else {
                                            Image(systemName: "app.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.secondary)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(app.name)
                                                .font(.system(size: 13, weight: .medium))
                                            Text(app.bundleIdentifier)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .task {
                        if scanner.installedApps.isEmpty {
                            _ = await scanner.scanInstalledApps()
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 380)
    }
}
