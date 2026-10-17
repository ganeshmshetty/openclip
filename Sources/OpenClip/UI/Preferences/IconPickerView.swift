// IconPickerView.swift
// OpenClip
//
// Renders an icon selection view supporting SF Symbols, open-source vector icon libraries,
// and user-provided custom icons (Finder uploads and website favicons).
import SwiftUI
import Core
import SDWebImage
import SDWebImageSVGCoder
import UniformTypeIdentifiers
import AppKit

// MARK: - IconPickerView

public struct IconPickerView: View {
    @Binding var selectedSymbol: String
    var onSelect: (() -> Void)? = nil
    /// Grids take all available height when true; false keeps the compact popover heights.
    var fillsAvailableHeight: Bool = false

    @StateObject private var provider = UnifiedIconProvider.shared
    @StateObject private var customIconManager = CustomIconManager.shared
    @State private var iconTab: IconTab = .native
    @State private var searchText = ""
    @State private var submittedQuery = ""          // updated on Enter for Open Source icons

    // Custom Tab State
    @State private var urlInput = ""
    @State private var isResolvingFavicon = false
    @State private var faviconErrorMessage: String? = nil

    enum IconTab { case native, openSource, custom }

    public init(
        selectedSymbol: Binding<String>,
        selectedText: Binding<String> = .constant(""),
        mode: Binding<Int> = .constant(0),
        fillsAvailableHeight: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self._selectedSymbol = selectedSymbol
        self.fillsAvailableHeight = fillsAvailableHeight
        self.onSelect = onSelect
    }

    private var gridMaxHeight: CGFloat { fillsAvailableHeight ? .infinity : 180 }
    private var savedGridMaxHeight: CGFloat { fillsAvailableHeight ? .infinity : 110 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $iconTab) {
                Text("Native Icons").tag(IconTab.native)
                Text("Open Source").tag(IconTab.openSource)
                Text("Custom").tag(IconTab.custom)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 2)

            Divider()

            switch iconTab {
            case .native:
                nativeIconsTab
            case .openSource:
                openSourceTab
            case .custom:
                customTab
            }

            if !selectedSymbol.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    AnyIconView(iconId: selectedSymbol)
                        .frame(width: 20, height: 20)
                    Text(selectedSymbol)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        selectedSymbol = ""
                        onSelect?()
                    } label: {
                        Text(String(localized: "Reset"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .onAppear {
            if selectedSymbol.hasPrefix(Constants.customIconPrefix) || selectedSymbol.hasPrefix("/") || selectedSymbol.hasPrefix("file:") {
                iconTab = .custom
            } else if selectedSymbol.contains(":") {
                iconTab = .openSource
            } else {
                iconTab = .native
            }
        }
    }

    // MARK: - Native Icons Tab (SF Symbols - Grid + Live Search)

    @ViewBuilder
    private var nativeIconsTab: some View {
        if !provider.sfLoaded {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading SF Symbols…").font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        } else {
            let sfResults: [IconEntry] = {
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if q.isEmpty { return provider.defaultIcons }
                return provider.sfSymbols.filter { $0.id.contains(q) }.prefix(160).map { $0 }
            }()

            VStack(alignment: .leading, spacing: 6) {
                NativeSearchField(
                    text: $searchText,
                    placeholder: String(localized: "Search SF Symbols…"),
                    controlSize: .small
                )
                .frame(height: 20)

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(sfResults) { item in
                            Button {
                                selectedSymbol = item.id
                                onSelect?()
                            } label: {
                                IconCellView(iconId: item.id, isSelected: selectedSymbol == item.id)
                            }
                            .buttonStyle(.plain)
                            .help(item.id)
                        }
                    }
                    .padding(2)
                }
                .scrollContentBackground(.hidden)
                .frame(maxHeight: gridMaxHeight)
            }
        }
    }

    // MARK: - Open Source Tab (Iconify - Grid + Search on Enter)

    @ViewBuilder
    private var openSourceTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Iconify query fires on Enter only.
            HStack(spacing: 6) {
                NativeSearchField(
                    text: $searchText,
                    placeholder: String(localized: "Search Iconify (press Enter)…"),
                    controlSize: .small
                ) { query in
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    submittedQuery = trimmed
                    if !trimmed.isEmpty {
                        provider.search(query: trimmed)
                    }
                }
                .onChange(of: searchText) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        submittedQuery = ""
                    }
                }
                .frame(height: 20)
                if provider.isSearching {
                    ProgressView().controlSize(.mini)
                }
            }

            if submittedQuery.isEmpty {
                VStack(spacing: 6) {
                    Text("Search to browse 50,000+ open source icons\n(Lucide, Tabler, Material Symbols, MDI…)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: gridMaxHeight)
            } else if provider.isSearching {
                VStack {
                    ProgressView("Searching Iconify…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: gridMaxHeight)
            } else {
                let openSourceResults = provider.searchResults.filter { $0.id.contains(":") }
                if openSourceResults.isEmpty {
                    VStack {
                        Text("No icons found for \"\(submittedQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: gridMaxHeight)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                            ForEach(openSourceResults) { item in
                                Button {
                                    selectedSymbol = item.id
                                    onSelect?()
                                } label: {
                                    IconCellView(iconId: item.id, isSelected: selectedSymbol == item.id)
                                }
                                .buttonStyle(.plain)
                                .help("\(item.id) (\(item.library))")
                            }
                        }
                        .padding(2)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: gridMaxHeight)
                }
            }
        }
    }

    // MARK: - Custom Tab (Finder Upload + Favicon Resolver + Saved Icons Grid)

    @ViewBuilder
    private var customTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Favicon from URL")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        TextField("Website URL (e.g. github.com)", text: $urlInput)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .onSubmit {
                                resolveFavicon()
                            }
                        if !urlInput.isEmpty {
                            Button {
                                urlInput = ""
                                faviconErrorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)

                    Button("Resolve") {
                        resolveFavicon()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolvingFavicon)

                    if isResolvingFavicon {
                        ProgressView().controlSize(.small)
                    }
                }

                if let error = faviconErrorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button {
                    chooseFileFromFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.doc")
                        Text("Upload from Finder…")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("PNG, SVG, JPG, ICNS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Saved Icons")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !customIconManager.customIcons.isEmpty {
                        Text("\(customIconManager.customIcons.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if customIconManager.customIcons.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("No custom icons yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Upload an image or enter a URL above")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: savedGridMaxHeight)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                            ForEach(customIconManager.customIcons, id: \.self) { iconId in
                                Button {
                                    selectedSymbol = iconId
                                    onSelect?()
                                } label: {
                                    IconCellView(iconId: iconId, isSelected: selectedSymbol == iconId)
                                }
                                .buttonStyle(.plain)
                                .help(iconId)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        customIconManager.deleteCustomIcon(named: iconId)
                                        if selectedSymbol == iconId {
                                            selectedSymbol = ""
                                        }
                                    } label: {
                                        Label("Delete Icon", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: savedGridMaxHeight)
                }
            }
        }
    }

    private func chooseFileFromFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .svg, .icns]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let savedId = try customIconManager.importIcon(from: url)
                self.selectedSymbol = savedId
                self.faviconErrorMessage = nil
                self.onSelect?()
            } catch {
                self.faviconErrorMessage = error.localizedDescription
                Log.icons.error("Failed to import custom icon: \(error.localizedDescription)")
            }
        }
    }

    private func resolveFavicon() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        faviconErrorMessage = nil
        isResolvingFavicon = true

        Task {
            do {
                let savedId = try await customIconManager.resolveFavicon(from: trimmed)
                self.selectedSymbol = savedId
                self.isResolvingFavicon = false
                self.onSelect?()
            } catch {
                self.isResolvingFavicon = false
                self.faviconErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Icon Cell View

struct IconCellView: View {
    let iconId: String
    let isSelected: Bool

    var body: some View {
        AnyIconView(iconId: iconId)
            .frame(width: 32, height: 32)
            .background(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .cornerRadius(6)
    }
}

// MARK: - AnyIconView

public struct AnyIconView: View {
    let iconId: String

    public init(iconId: String) {
        self.iconId = iconId
    }

    public var body: some View {
        ActionIconView(icon: ActionIcon.resolve(from: iconId), size: 16)
    }
}

// MARK: - Iconify SVG Renderer (Decodes SVG & sets template=true for pure white vector rendering)

struct IconifySVGView: View {
    let iconId: String

    private enum LoadState {
        case loading
        case loaded(NSImage)
        case failed
    }
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loaded(let img):
                Image(nsImage: img)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            case .loading:
                Color.primary.opacity(0.1)
                    .overlay(ProgressView().controlSize(.mini))
            case .failed:
                // Never spin forever; the fetch is retried the next time the view appears.
                Image(systemName: "questionmark.square")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
            }
        }
        .task(id: iconId) {
            let box = await IconifySVGLoader.shared.image(for: iconId)
            guard !Task.isCancelled else { return }
            if let box {
                state = .loaded(box.image)
            } else {
                state = .failed
            }
        }
    }
}

// MARK: - Iconify SVG Loader

/// `NSImage` is not Sendable; the box is fully decoded before it crosses to the main actor.
struct IconImageBox: @unchecked Sendable {
    let image: NSImage
}

/// Loads Iconify SVGs with bounded concurrency, a per-request timeout, and retries with backoff.
/// Successes are cached for the session; failures only for `IconifyFetchPolicy.failureCooldown`.
actor IconifySVGLoader {
    static let shared = IconifySVGLoader()

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let fetch: Fetch

    init(fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.fetch = fetch
    }

    private enum Attempt {
        case loaded(IconImageBox)
        case retry
        case giveUp
    }

    private var images: [String: IconImageBox] = [:]
    private var failures: [String: Date] = [:]
    private var inFlight: [String: Task<IconImageBox?, Never>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func image(for iconId: String) async -> IconImageBox? {
        if let cached = images[iconId] { return cached }
        if let failedAt = failures[iconId],
           IconifyFetchPolicy.isCoolingDown(failedAt: failedAt, now: Date()) {
            return nil
        }
        if let running = inFlight[iconId] { return await running.value }
        guard let url = IconifyFetchPolicy.svgURL(for: iconId) else { return nil }

        // Unstructured so a grid cell scrolling away does not cancel a fetch other cells may be awaiting.
        let task = Task { await self.load(iconId: iconId, url: url) }
        inFlight[iconId] = task
        let result = await task.value
        inFlight[iconId] = nil
        if let result {
            images[iconId] = result
            failures[iconId] = nil
        } else {
            failures[iconId] = Date()
        }
        return result
    }

    private func load(iconId: String, url: URL) async -> IconImageBox? {
        for attempt in 0..<IconifyFetchPolicy.maxAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: IconifyFetchPolicy.backoffNanoseconds(beforeAttempt: attempt))
            }
            // The slot is held only for the request itself, never across a backoff sleep.
            await acquireSlot()
            let outcome = await fetchOnce(iconId: iconId, url: url)
            releaseSlot()
            switch outcome {
            case .loaded(let box):
                return box
            case .retry:
                continue
            case .giveUp:
                return nil
            }
        }
        Log.icons.debug("Giving up on icon '\(iconId, privacy: .public)' after repeated failures")
        return nil
    }

    private func fetchOnce(iconId: String, url: URL) async -> Attempt {
        let request = URLRequest(url: url, timeoutInterval: IconifyFetchPolicy.requestTimeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            Log.icons.debug("Failed to download icon '\(iconId, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return IconifyFetchPolicy.shouldRetry(urlErrorCode: (error as? URLError)?.code) ? .retry : .giveUp
        }
        if let http = response as? HTTPURLResponse {
            switch IconifyFetchPolicy.outcome(forStatusCode: http.statusCode) {
            case .success:
                break
            case .retry:
                return .retry
            case .giveUp:
                return .giveUp
            }
        }
        guard let decoded = SDImageSVGCoder.shared.decodedImage(with: data, options: nil) else {
            Log.icons.debug("Could not decode SVG for icon '\(iconId, privacy: .public)'")
            return .giveUp
        }
        // Template image: rendered as a tintable vector mask.
        decoded.isTemplate = true
        return .loaded(IconImageBox(image: decoded))
    }

    private func acquireSlot() async {
        if activeRequests < IconifyFetchPolicy.maxConcurrentRequests {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands a freed slot straight to the oldest waiter, so `activeRequests` stays at the cap while any wait.
    private func releaseSlot() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Minimalistic Popover Wrapper

/// Compact inline icon picker for settings pages.
public struct IconPickerPopover: View {
    @Binding public var selectedSymbol: String
    public var onSelect: (() -> Void)?

    public init(selectedSymbol: Binding<String>, onSelect: (() -> Void)? = nil) {
        self._selectedSymbol = selectedSymbol
        self.onSelect = onSelect
    }

    public var body: some View {
        IconPickerView(
            selectedSymbol: $selectedSymbol,
            fillsAvailableHeight: false,
            onSelect: onSelect
        )
        .padding(12)
        .frame(width: 320, height: 320)
    }
}
