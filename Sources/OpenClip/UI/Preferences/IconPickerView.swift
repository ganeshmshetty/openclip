import SwiftUI
import Core

public enum IconSelectionMode {
    case symbol
    case text
}

public struct IconPickerView: View {
    @Binding var selectedSymbol: String
    @Binding var selectedText: String
    @Binding var mode: Int // 0 = SF Symbol, 1 = Text / Emoji

    @StateObject private var symbolProvider = DynamicSFSymbolProvider.shared
    @State private var searchText = ""

    public init(selectedSymbol: Binding<String>, selectedText: Binding<String>, mode: Binding<Int>) {
        self._selectedSymbol = selectedSymbol
        self._selectedText = selectedText
        self._mode = mode
    }

    private var displayedIcons: [String] {
        return symbolProvider.search(query: searchText, limit: 120)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $mode) {
                Text("SF Symbol").tag(0)
                Text("Emoji / Text").tag(1)
            }
            .pickerStyle(.segmented)

            if mode == 0 {
                // System Dynamic SF Symbol Search Bar
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search \(symbolProvider.allSymbols.count)+ system symbols...", text: $searchText)
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

                    TextField("Symbol name", text: $selectedSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }

                if !symbolProvider.isLoaded {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanning macOS system symbols…")
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
                                    Image(systemName: sym)
                                        .font(.system(size: 15))
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
