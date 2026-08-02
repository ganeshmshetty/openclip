// ExtensionsStoreView.swift
// OpenClip
//
// Renders the extension store browser, installed extensions manager, and installer interface in preferences.
import SwiftUI
import Core

enum ExtensionSubTab: String, CaseIterable, Identifiable {
    case store = "Store"
    case installed = "Installed"
    var id: String { rawValue }
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
    @StateObject private var viewModel = ExtensionsStoreViewModel()
    @State private var selectedSubTab: ExtensionSubTab = .store
    @ObservedObject private var coordinator = ActionCoordinator.shared

    public init() {}

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
            // Segmented Header Switch (Store | Installed)
            HStack {
                Picker("", selection: $selectedSubTab) {
                    Text("Store").tag(ExtensionSubTab.store)
                    Text("Installed (\(installedExtensionActions.count))").tag(ExtensionSubTab.installed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                Button(action: {
                    openInstallExtensionPanel()
                }) {
                    Label("Install from File…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if selectedSubTab == .store {
                storeView
            } else {
                installedView
            }
        }
        .task {
            await viewModel.resetAndFetch()
        }
    }

    // MARK: - Store View
    private var storeView: some View {
        VStack(spacing: 12) {
            // Search Header Bar
            HStack(spacing: 10) {
                TextField("Search extensions...", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.searchQuery) { _ in
                        Task { await viewModel.resetAndFetch() }
                    }
                
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("All").tag("All")
                    Text("Productivity").tag("Productivity")
                    Text("Developer").tag("Developer")
                    Text("Utilities").tag("Utilities")
                }
                .frame(width: 140)
                .onChange(of: viewModel.selectedCategory) { _ in
                    Task { await viewModel.resetAndFetch() }
                }
                
                Button(action: {
                    if let url = URL(string: "https://getopenclip.vercel.app/extensions") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Open Web Store", systemImage: "globe")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Cards Grid with Lazy Loading
            if viewModel.extensions.isEmpty && !viewModel.isLoading {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No extensions found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 12) {
                        ForEach(viewModel.extensions) { ext in
                            ExtensionCardView(item: ext)
                                .onAppear {
                                    if ext.id == viewModel.extensions.last?.id {
                                        Task { await viewModel.fetchNextPage() }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
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
                    Text("Browse the Store tab or click 'Install from File...' to add extensions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(installedExtensionActions, id: \.id) { action in
                        HStack(spacing: 12) {
                            ZStack {
                                if case .symbol(let name) = action.displayIcon {
                                    Image(systemName: name)
                                        .font(.system(size: 14))
                                } else {
                                    Image(systemName: "puzzlepiece.extension.fill")
                                        .font(.system(size: 14))
                                }
                            }
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.displayTitle)
                                    .font(.system(size: 13, weight: .medium))

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
                                Label("Remove", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal)
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
        ActionCoordinator.shared.actions.first { $0.id.contains(item.id) }
    }

    private var isInstalled: Bool {
        matchingInstalledAction != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.icon.hasPrefix("symbol:") ? String(item.icon.dropFirst(7)) : item.icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline)
                    Text("by \(item.author)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            Text(item.description)
                .font(.caption)
                .lineLimit(2)
                .foregroundColor(.secondary)

            if let err = installError {
                Text("⚠︎ \(err)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack {
                Text(item.downloadCount > 0 ? "⬇ \(item.downloadCount)" : "New")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}
