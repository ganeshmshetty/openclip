import SwiftUI
import Core

public struct IconPickerView: View {
    @Binding var selectedSymbol: String
    @Binding var selectedText: String
    @Binding var mode: Int // 0 = Icon Library, 1 = Text / Emoji

    @StateObject private var provider = DynamicSFSymbolProvider.shared
    @State private var selectedLibrary: IconLibraryType = .sfSymbols
    @State private var searchText = ""

    public init(selectedSymbol: Binding<String>, selectedText: Binding<String>, mode: Binding<Int>) {
        self._selectedSymbol = selectedSymbol
        self._selectedText = selectedText
        self._mode = mode
    }

    private var displayedIcons: [String] {
        return provider.search(library: selectedLibrary, query: searchText, limit: 120)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $mode) {
                Text("Icon Libraries").tag(0)
                Text("Emoji / Text").tag(1)
            }
            .pickerStyle(.segmented)

            if mode == 0 {
                // Library selector tabs
                Picker("Library", selection: $selectedLibrary) {
                    ForEach(IconLibraryType.allCases) { lib in
                        Text(lib.rawValue).tag(lib)
                    }
                }
                .pickerStyle(.segmented)

                // Search Bar
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search \(selectedLibrary.rawValue)...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)

                    TextField("Icon code/name", text: $selectedSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                if !provider.isLoaded {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading icon libraries…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                            ForEach(displayedIcons, id: \.self) { sym in
                                Button {
                                    selectedSymbol = sym
                                } label: {
                                    RenderIconView(iconStr: sym)
                                        .frame(width: 32, height: 32)
                                        .background(selectedSymbol == sym ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedSymbol == sym ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help(sym)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 180)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter Emoji or Text (e.g. 🔍, ⚡️, 🎵, ⌘C, UPPER)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Emoji / Text", text: $selectedText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

/// Renders either SF Symbol or fallback text badge for FA / Lucide / Material codes
struct RenderIconView: View {
    let iconStr: String

    var body: some View {
        if iconStr.contains(":") {
            let parts = iconStr.components(separatedBy: ":")
            let prefix = parts.first?.uppercased() ?? "ICO"
            Text(prefix.prefix(2))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
        } else {
            Image(systemName: (try? iconStr) ?? "questionmark")
                .font(.system(size: 15))
        }
    }
}
