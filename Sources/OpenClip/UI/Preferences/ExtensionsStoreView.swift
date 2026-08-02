// ExtensionsStoreView.swift
// OpenClip
//
// Renders the extension store browser, installed extensions manager, and installer interface in preferences.
import SwiftUI
import Core

public enum ExtensionSubTab: String, CaseIterable, Identifiable, Sendable {
    case store = "Store"
    case installed = "Installed"
    public var id: String { rawValue }
}

@MainActor
public final class ExtensionsStoreViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var selectedCategory: String = "All"
    @Published public var extensions: [ExtensionItem] = []
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    
    public init() {}
    
    public func fetchNextPage() async {
        guard !isLoading, currentPage <= totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        
        if let response = try? await ExtensionsAPIClient.shared.fetchExtensions(query: searchQuery, category: selectedCategory, page: currentPage) {
            self.extensions.append(contentsOf: response.extensions)
            self.totalPages = response.totalPages
            self.currentPage += 1
        }
    }
    
    public func resetAndFetch() async {
        self.currentPage = 1
        self.extensions = []
        await fetchNextPage()
    }
}

public struct ExtensionsStoreView: View {
    @Binding var selectedSubTab: ExtensionSubTab
    @StateObject private var viewModel = ExtensionsStoreViewModel()
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init(selectedSubTab: Binding<ExtensionSubTab> = .constant(.store)) {
        self._selectedSubTab = selectedSubTab
    }

    private var installedExtensionActions: [any Action] {
        coordinator.actions.filter { action in
            if case .extensionPkg = action.chrome.badge {
                return true
            }
            if case .extensionPkg = action.chrome.source {
                return true
            }
            return false
        }
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Filter Control Bar
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    TextField("Search extensions...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: viewModel.searchQuery) { _ in
                            Task { await viewModel.resetAndFetch() }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

                // Category Selector
                Picker("", selection: $viewModel.selectedCategory) {
                    Text("All Categories").tag("All")
                    Text("Productivity").tag("Productivity")
                    Text("Developer").tag("Developer")
                    Text("Utilities").tag("Utilities")
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .onChange(of: viewModel.selectedCategory) { _ in
                    Task { await viewModel.resetAndFetch() }
                }

                Spacer()

                // Install from File Button
                Button(action: {
                    openInstallExtensionPanel()
                }) {
                    Label("Install File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 4)

            // Content View
            if selectedSubTab == .store {
                storeView
            } else {
                installedView
            }
        }
        .padding(12)
        .task {
            await viewModel.resetAndFetch()
        }
    }

    // MARK: - Store View
    private var storeView: some View {
        VStack(spacing: 0) {
            if viewModel.extensions.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No extensions found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    let twoColumns = [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ]
                    LazyVGrid(columns: twoColumns, spacing: 14) {
                        ForEach(viewModel.extensions) { ext in
                            ExtensionCardView(item: ext)
                                .onAppear {
                                    if ext.id == viewModel.extensions.last?.id {
                                        Task { await viewModel.fetchNextPage() }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    // MARK: - Installed View
    private var installedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if installedExtensionActions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Extensions Installed")
                        .font(.headline)
                    Text("Browse the Store tab or click 'Install File...' to add extensions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(installedExtensionActions, id: \.id) { action in
                        HStack(spacing: 12) {
                            ZStack {
                                if case .symbol(let name) = action.displayIcon {
                                    Image(systemName: name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)
                                } else {
                                    Image(systemName: "puzzlepiece.extension.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.displayTitle)
                                    .font(.system(size: 13, weight: .semibold))

                                switch action.chrome.badge {
                                case .extensionPkg(let pkgName):
                                    Text(pkgName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                default:
                                    Text("Extension Package")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(role: .destructive, action: {
                                uninstallExtension(actionID: action.id)
                            }) {
                                Label("Uninstall", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func uninstallExtension(actionID: String) {
        Task {
            try? await ExtensionManager.shared.uninstallExtension(actionID: actionID)
            await MainActor.run {
                NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
            }
        }
    }

    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Extension to Install"
        panel.message = "Choose a .openclipext folder, .zip archive, or script file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    await MainActor.run {
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

struct ExtensionCardView: View {
    let item: ExtensionItem
    @State private var isInstalling = false
    @State private var installError: String? = nil
    @State private var showSuccess = false

    private var matchingInstalledAction: (any Action)? {
        // Generated action IDs are "<manifest.identifier>.action.<n>", store item.id is "<manifest.identifier>"
        // So we match when the action.id starts with item.id (e.g. "com.openclip.applemusic.action.0" starts with "com.openclip.applemusic")
        ActionCoordinator.shared.actions.first { action in
            let actID = action.id.lowercased()
            let itemID = item.id.lowercased()
            let actTitle = action.displayTitle.lowercased()
            let itemName = item.name.lowercased()
            return actID.hasPrefix(itemID) || itemID.hasPrefix(actID) || actTitle == itemName
        }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon + Name & Author
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: item.icon.hasPrefix("symbol:") ? String(item.icon.dropFirst(7)) : item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text("@\(item.author)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // Description
            Text(item.description)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(.secondary)
                .frame(minHeight: 32, alignment: .topLeading)

            if let err = installError {
                Text("⚠︎ \(err)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Footer Row: Downloads Pill & Action Button
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.caption2)
                    Text(item.downloadCount > 0 ? "\(item.downloadCount)" : "New")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))

                Spacer()

                if showSuccess || isInstalled {
                    Button(role: .destructive, action: {
                        if let action = matchingInstalledAction {
                            Task {
                                try? await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                                await MainActor.run {
                                    showSuccess = false
                                    NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                                }
                            }
                        }
                    }) {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                } else {
                    Button(isInstalling ? "Installing..." : "Install") {
                        guard let url = URL(string: item.downloadURL) else {
                            installError = "Invalid download URL."
                            return
                        }
                        isInstalling = true
                        installError = nil
                        Task {
                            do {
                                _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                                showSuccess = true
                            } catch {
                                installError = error.localizedDescription
                            }
                            isInstalling = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isInstalling)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
