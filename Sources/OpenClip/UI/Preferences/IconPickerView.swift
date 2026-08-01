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
    
    @State private var searchText = ""
    @State private var selectedCategory = 0
    
    public static let iconCategories: [(name: String, icons: [String])] = [
        ("Common", [
            "doc.on.clipboard", "scissors", "doc.text", "magnifyingglass", "wand.and.stars",
            "link", "globe", "envelope", "square.and.pencil", "arrow.up.circle",
            "checkmark.circle", "xmark.circle", "star", "heart", "bookmark",
            "tag", "paperplane", "tray.and.arrow.up", "tray.and.arrow.down", "archivebox"
        ]),
        ("Text & Writing", [
            "textformat", "bold", "italic", "underline", "strikethrough",
            "textformat.size", "character.cursor.ibeam", "text.quote", "list.bullet",
            "list.number", "text.alignleft", "text.aligncenter", "text.alignright",
            "text.justify", "pencil", "pencil.circle", "pencil.and.outline",
            "square.and.pencil", "note.text", "doc.plaintext", "doc.richtext"
        ]),
        ("Search & Web", [
            "magnifyingglass", "magnifyingglass.circle", "safari", "globe", "network",
            "link.circle", "link.badge.plus", "arrow.up.right.square", "externaldrive.connected.to.line.below",
            "books.vertical", "book", "book.circle", "map", "location", "location.circle"
        ]),
        ("Math & Code", [
            "function", "x.squareroot", "percent", "plusminus", "sum",
            "chevron.left.forwardslash.chevron.right", "terminal", "curlybraces",
            "hammer", "gear", "gearshape", "wrench.and.screwdriver", "cpu",
            "memorychip", "number", "number.circle"
        ]),
        ("Media & Sharing", [
            "square.and.arrow.up", "square.and.arrow.down", "arrow.clockwise",
            "arrow.counterclockwise", "arrow.right.circle", "arrowshape.turn.up.right",
            "speaker.wave.2", "mic", "camera", "photo", "video", "play.circle",
            "pause.circle", "stop.circle", "record.circle"
        ]),
        ("Symbols", [
            "star.circle", "flame", "bolt", "sparkles", "waveform",
            "cube", "cube.transparent", "shippingbox", "lock", "lock.open",
            "key", "shield", "shield.checkered", "exclamationmark.circle",
            "questionmark.circle", "info.circle", "bell", "flag"
        ])
    ]
    
    public init(selectedSymbol: Binding<String>, selectedText: Binding<String>, mode: Binding<Int>) {
        self._selectedSymbol = selectedSymbol
        self._selectedText = selectedText
        self._mode = mode
    }
    
    private var displayedIcons: [String] {
        if !searchText.isEmpty {
            let all = IconPickerView.iconCategories.flatMap { $0.icons }
            return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        guard selectedCategory < IconPickerView.iconCategories.count else { return [] }
        return IconPickerView.iconCategories[selectedCategory].icons
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $mode) {
                Text("SF Symbol").tag(0)
                Text("Emoji / Text").tag(1)
            }
            .pickerStyle(.segmented)
            
            if mode == 0 {
                // SF Symbol Search & Filter
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search 100+ SF Symbols...", text: $searchText)
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
                
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<IconPickerView.iconCategories.count, id: \.self) { idx in
                                Button(IconPickerView.iconCategories[idx].name) {
                                    selectedCategory = idx
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: selectedCategory == idx ? .bold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedCategory == idx ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                                .foregroundColor(selectedCategory == idx ? .accentColor : .primary)
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(displayedIcons, id: \.self) { sym in
                            Button {
                                selectedSymbol = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 14))
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
                .frame(maxHeight: 150)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter Emoji or Text (e.g. Aa, 🔍, ⚡️, ⌘C)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Emoji / Text", text: $selectedText)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
