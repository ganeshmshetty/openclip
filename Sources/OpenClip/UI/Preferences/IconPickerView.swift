import SwiftUI
import Core

public struct IconPickerView: View {
    @Binding var selectedSymbol: String
    @Binding var selectedText: String
    @Binding var mode: Int // 0 = All Icons (Unified), 1 = Text / Emoji

    @StateObject private var provider = UnifiedIconProvider.shared
    @State private var searchText = ""

    public init(selectedSymbol: Binding<String>, selectedText: Binding<String>, mode: Binding<Int>) {
        self._selectedSymbol = selectedSymbol
        self._selectedText = selectedText
        self._mode = mode
    }

    private var displayedIcons: [IconEntry] {
        return provider.search(query: searchText, limit: 160)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $mode) {
                Text("All Icons (Unified)").tag(0)
                Text("Emoji / Text").tag(1)
            }
            .pickerStyle(.segmented)

            if mode == 0 {
                // Unified Search Bar — Queries ALL libraries simultaneously
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search \(provider.allIcons.count)+ icons (SF Symbols, FA, Lucide, Material)...", text: $searchText)
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

                    TextField("Icon ID / Name", text: $selectedSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                if !provider.isLoaded {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanning all icon libraries…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                            ForEach(displayedIcons) { item in
                                Button {
                                    selectedSymbol = item.id
                                } label: {
                                    RenderIconView(iconStr: item.id)
                                        .frame(width: 32, height: 32)
                                        .background(selectedSymbol == item.id ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedSymbol == item.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .help("\(item.id) (\(item.library))")
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
