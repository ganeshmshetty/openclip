// ExtensionsStoreView.swift
// OpenClip
//
// Provides the extension store browsing view for the Actions tab in preferences,
// plus the shared view model used by onboarding. Formatted in a unified native macOS inset table.
import SwiftUI
import Core

@MainActor
public final class ExtensionsStoreViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var extensions: [ExtensionItem] = []
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1

    /// Monotonic result-set generation. Every reset bumps it; any response that resolves
    /// against a superseded generation is discarded, so a slow earlier request landing late
    /// (fast typing, page prefetch racing a new search) can never surface stale rows.
    private var generation = 0
    /// In-flight debounced search; cancelled when the query changes again.
    private var searchTask: Task<Void, Never>?
    private let api: any ExtensionStoreFetching
    /// Keystroke quiet period before a search actually fires.
    private let debounceNanos: UInt64
    /// Page size for the active fetch session; onboarding raises it so one request
    /// covers the whole catalog and curated picks are always in the result set.
    private var pageLimit: Int = Constants.storePageLimit

    public init(api: any ExtensionStoreFetching = ExtensionsAPIClient.shared,
                debounceNanos: UInt64 = 250_000_000) {
        self.api = api
        self.debounceNanos = debounceNanos
    }

    deinit { searchTask?.cancel() }

    /// Debounced, cancellable search entry point for per-keystroke changes. Coalesces rapid
    /// typing into one request and cancels any in-flight one; the view calls this from
    /// `onChange(of: searchQuery)` instead of spawning its own unstructured task.
    public func queryDidChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanos)
            guard !Task.isCancelled else { return }
            await self.resetAndFetch(keepPrevious: true)
        }
    }

    public func fetchNextPage(isReset: Bool = false) async {
        let gen = generation
        guard !isLoading || isReset, currentPage <= totalPages else { return }
        isLoading = true

        do {
            let response = try await api.fetchExtensions(query: searchQuery, page: currentPage, limit: pageLimit)
            // Superseded mid-flight (newer search/reset owns the result set): touch nothing,
            // especially not `isLoading`, which now belongs to the winning generation.
            guard gen == generation else { return }
            if isReset {
                extensions = response.extensions
            } else {
                extensions.append(contentsOf: response.extensions)
            }
            totalPages = response.totalPages
            currentPage += 1
            isLoading = false
        } catch is CancellationError {
            // Superseded or torn down; the winner manages its own state.
        } catch {
            guard gen == generation else { return }
            Log.extensions.warning("Failed to fetch extension store page \(self.currentPage) for query '\(self.searchQuery)'")
            if isReset && extensions.isEmpty {
                extensions = []
            }
            isLoading = false
        }
    }

    public func resetAndFetch(limit: Int = Constants.storePageLimit, keepPrevious: Bool = false) async {
        // Bump first: any in-flight request from the previous generation is dead on arrival
        // and can neither append rows nor hold the loading flag against this fetch.
        generation += 1
        pageLimit = limit
        currentPage = 1
        totalPages = 1
        if !keepPrevious {
            extensions = []
        }
        isLoading = true
        await fetchNextPage(isReset: true)
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
                        viewModel.queryDidChange()
                    }
                if viewModel.isLoading && !viewModel.extensions.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
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
        .padding(.horizontal, 2)
    }

    private var storeContent: some View {
        VStack(spacing: 0) {
            if viewModel.extensions.isEmpty && viewModel.isLoading {
                skeletonList
            } else if viewModel.extensions.isEmpty {
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
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.extensions.enumerated()), id: \.element.id) { index, ext in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 60)
                                    .padding(.trailing, 14)
                            }
                            ExtensionCardView(item: ext)
                                .onAppear {
                                    if ext.id == viewModel.extensions.last?.id {
                                        Task { await viewModel.fetchNextPage() }
                                    }
                                }
                        }
                    }
                }
                .opacity(viewModel.isLoading && !viewModel.extensions.isEmpty ? 0.65 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var skeletonList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 14)
                    }
                    ExtensionCardSkeletonRow()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Extension Card Skeleton Row

private struct ExtensionCardSkeletonRow: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 110, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 60, height: 10)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 220, height: 11)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 64, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(isPulsing ? 0.35 : 0.85)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
