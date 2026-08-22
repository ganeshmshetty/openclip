// ExtensionsStoreView.swift
// OpenClip
//
// Provides the extension store browsing view for the merged Actions tab in preferences,
// plus the shared view model used by onboarding. The installed-extensions list and the
// store card moved to InstalledExtensionsView.swift / ExtensionCardView.swift; the shared
// install-file panel lives in ExtensionInstallPanel.swift.
import SwiftUI
import Core

@MainActor
public final class ExtensionsStoreViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var extensions: [ExtensionItem] = []
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    
    public init() {}
    
    public func fetchNextPage() async {
        guard !isLoading, currentPage <= totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        
        if let response = try? await ExtensionsAPIClient.shared.fetchExtensions(query: searchQuery, page: currentPage) {
            self.extensions.append(contentsOf: response.extensions)
            self.totalPages = response.totalPages
            self.currentPage += 1
        } else {
            Log.extensions.warning("Failed to fetch extension store page \(self.currentPage) for query '\(self.searchQuery)'")
        }
    }
    
    public func resetAndFetch() async {
        self.currentPage = 1
        self.extensions = []
        await fetchNextPage()
    }
}

public struct ExtensionStoreView: View {
    @StateObject private var viewModel = ExtensionsStoreViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            filterBar
            storeContent
        }
        .padding(12)
        .task {
            await viewModel.resetAndFetch()
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search extensions...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: viewModel.searchQuery) { _, _ in
                        Task { await viewModel.resetAndFetch() }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            Spacer()

            Button(action: {
                presentInstallExtensionPanel()
            }) {
                Label("Install File…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 4)
    }

    private var storeContent: some View {
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
                    let singleColumn = [
                        GridItem(.flexible(), spacing: 8)
                    ]
                    LazyVGrid(columns: singleColumn, spacing: 8) {
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
}
