// AppPickerSheet.swift
// OpenClip
//
// Renders an application picker sheet allowing users to select running or installed applications for rule configuration.
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
    
    private var allApps: [InstalledAppInfo] {
        var map = [String: InstalledAppInfo]()
        
        for app in scanner.installedApps {
            map[app.bundleIdentifier] = app
        }
        
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy == .regular,
               let bid = app.bundleIdentifier,
               bid != "com.openclip.OpenClip",
               map[bid] == nil {
                let name = app.localizedName ?? bid
                let path = app.bundleURL?.path ?? ""
                map[bid] = InstalledAppInfo(name: name, bundleIdentifier: bid, path: path)
            }
        }
        
        return Array(map.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var filteredApps: [InstalledAppInfo] {
        if searchText.isEmpty { return allApps }
        return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar with Close Button
            HStack {
                Text("Add Application Rule")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            Picker("", selection: $selectedTab) {
                Text("Applications").tag(0)
                Text("Custom").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            if selectedTab == 1 {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enter Bundle Identifier")
                            .font(.headline)
                        Text("Example: com.apple.Terminal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("e.g. com.apple.Terminal", text: $customBundleID)
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
                
                Group {
                    if scanner.isLoading && scanner.installedApps.isEmpty {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading applications...").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredApps) { app in
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
                
                Divider()
                
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .controlSize(.small)
                }
                .padding(8)
            }
        }
        .frame(width: 380, height: 410)
    }
}
