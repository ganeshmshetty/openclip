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
    /// True when the picker is a page of its own and the grids may take all the height they are
    /// given; false keeps the compact heights the picker had inside a popover.
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

    /// Height of the icon grids: the page lets them grow, the compact layout caps them.
    private var gridMaxHeight: CGFloat { fillsAvailableHeight ? .infinity : 180 }
    private var savedGridMaxHeight: CGFloat { fillsAvailableHeight ? .infinity : 110 }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segmented tab control (Native Icons | Open Source | Custom)
            Picker("", selection: $iconTab) {
                Text("Native Icons").tag(IconTab.native)
                Text("Open Source").tag(IconTab.openSource)
                Text("Custom").tag(IconTab.custom)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 2)

            Divider()

            // Active Tab Content
            switch iconTab {
            case .native:
                nativeIconsTab
            case .openSource:
                openSourceTab
            case .custom:
                customTab
            }

            // Preview footer for selected icon
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
                .frame(maxHeight: gridMaxHeight)
            }
        }
    }

    // MARK: - Open Source Tab (Iconify - Grid + Search on Enter)

    @ViewBuilder
    private var openSourceTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search field - fires Iconify query only when Enter is pressed
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
                    // Grid display for Open Source icons
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
                    .frame(maxHeight: gridMaxHeight)
                }
            }
        }
    }

    // MARK: - Custom Tab (Finder Upload + Favicon Resolver + Saved Icons Grid)

    @ViewBuilder
    private var customTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Favicon from URL
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

            // Upload from Finder
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

            // Saved Custom Icons Grid
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
    @State private var image: NSImage? = nil

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Color.primary.opacity(0.1)
                    .overlay(ProgressView().controlSize(.mini))
            }
        }
        .task(id: iconId) {
            if let box = await fetchSVGImage(iconId: iconId) {
                image = box.image
            }
        }
    }

    /// Fetches and decodes an Iconify SVG entirely off the main actor: `nonisolated` runs on the
    /// cooperative thread pool, `URLSession` performs the network I/O without blocking the UI, and
    /// the SVG decode (synchronous CPU work) also happens off-main. Previously `Data(contentsOf:)`
    /// blocked the main thread for the whole fetch on the view's main-actor task.
    private nonisolated func fetchSVGImage(iconId: String) async -> IconImageBox? {
        if let cached = await IconSVGCache.shared.get(iconId) { return cached }

        let parts = iconId.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let url = URL(string: "https://api.iconify.design/\(parts[0])/\(parts[1]).svg") else {
            return nil
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            Log.icons.debug("Failed to download icon '\(iconId)': \(error.localizedDescription)")
            return nil
        }

        // Use SDImageSVGCoder to decode raw SVG data into an NSImage (off the main actor)
        guard let decoded = SDImageSVGCoder.shared.decodedImage(with: data, options: nil) else {
            return nil
        }

        // Set as template so AppKit / SwiftUI renders it as a white vector mask
        decoded.isTemplate = true
        let box = IconImageBox(image: decoded)
        await IconSVGCache.shared.set(iconId, box: box)
        return box
    }
}

// MARK: - Icon Cache Actor

/// Boxes a decoded icon so it can cross the actor boundary after off-main decoding. `NSImage` is
/// not `Sendable`, but the image is fully decoded off-main and only handed to the main-actor view
/// to render, so this transfer is safe.
fileprivate struct IconImageBox: @unchecked Sendable {
    let image: NSImage
}

fileprivate actor IconSVGCache {
    static let shared = IconSVGCache()
    private var store: [String: IconImageBox] = [:]
    func get(_ key: String) -> IconImageBox? { store[key] }
    func set(_ key: String, box: IconImageBox) { store[key] = box }
}
