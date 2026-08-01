import SwiftUI
import Core

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
    
    public init() {}
    
    public var body: some View {
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
                
                Button("🌐 Open Web Store") {
                    if let url = URL(string: "https://openclip.app/extensions") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
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
        .task {
            await viewModel.resetAndFetch()
        }
    }
}

struct ExtensionCardView: View {
    let item: ExtensionItem
    @State private var isInstalling = false
    
    var isInstalled: Bool {
        ActionRegistry.shared.actions.contains { $0.id.contains(item.id) }
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
            
            HStack {
                Text("⬇ \(item.downloadCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                
                if isInstalled {
                    Text("Installed ✓")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button(isInstalling ? "Installing..." : "Install") {
                        if let url = URL(string: item.downloadURL) {
                            isInstalling = true
                            Task {
                                _ = try? await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: item.id)
                                isInstalling = false
                            }
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
