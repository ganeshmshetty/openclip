// IconPickerView.swift
// OpenClip
//
// Renders an icon selection view supporting SF Symbols and open-source vector icon libraries.
import SwiftUI
import Core
import SDWebImage
import SDWebImageSVGCoder

// MARK: - IconPickerView

public struct IconPickerView: View {
    @Binding var selectedSymbol: String
    var onSelect: (() -> Void)? = nil

    @StateObject private var provider = UnifiedIconProvider.shared
    @State private var iconTab: IconTab = .native
    @State private var searchText = ""
    @State private var submittedQuery = ""          // updated on Enter for Open Source icons

    enum IconTab { case native, openSource }

    public init(selectedSymbol: Binding<String>, selectedText: Binding<String> = .constant(""), mode: Binding<Int> = .constant(0), onSelect: (() -> Void)? = nil) {
        self._selectedSymbol = selectedSymbol
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segmented tab control (Native Icons | Open Source)
            Picker("", selection: $iconTab) {
                Text("Native Icons").tag(IconTab.native)
                Text("Open Source").tag(IconTab.openSource)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 2)

            Divider()

            // Active Tab Content
            if iconTab == .native {
                nativeIconsTab
            } else {
                openSourceTab
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
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("Search SF Symbols…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(5)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(5)

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
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Open Source Tab (Iconify - Grid + Search on Enter)

    @ViewBuilder
    private var openSourceTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Search field - fires Iconify query only when Enter is pressed
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField("Search Iconify (press Enter)…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit {
                        submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        provider.search(query: submittedQuery)
                    }
                if provider.isSearching {
                    ProgressView().controlSize(.mini)
                } else if !searchText.isEmpty {
                    Button { searchText = ""; submittedQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(5)

            if submittedQuery.isEmpty {
                VStack(spacing: 6) {
                    Text("Search to browse 50,000+ open source icons\n(Lucide, Tabler, Material Symbols, MDI…)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: 180)
            } else if provider.isSearching {
                VStack {
                    ProgressView("Searching Iconify…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 180)
            } else {
                let openSourceResults = provider.searchResults.filter { $0.id.contains(":") }
                if openSourceResults.isEmpty {
                    VStack {
                        Text("No icons found for \"\(submittedQuery)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
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
                    .frame(maxHeight: 180)
                }
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
        if iconId.contains(":") {
            IconifySVGView(iconId: iconId)
        } else {
            Image(systemName: iconId.isEmpty ? "star" : iconId)
                .resizable()
                .scaledToFit()
        }
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
