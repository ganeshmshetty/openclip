import SwiftUI
import Core

// Curated SF Symbols grouped by category for the icon picker
private let iconCategories: [(name: String, icons: [String])] = [
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

@MainActor
public struct AddCustomActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var typeIndex = 0
    @State private var title = ""
    @State private var iconName = "wand.and.stars"
    @State private var showingIconPicker = false
    
    // Web Search
    @State private var urlTemplate = "https://google.com/search?q={text}"
    
    // Text Snippet
    @State private var snippetTemplate = "**{text}**"
    
    // Shell Script
    @State private var shellScript = "echo \"$POPCLIP_TEXT\" | tr '[:lower:]' '[:upper:]'"
    @State private var replaceSelection = false
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            Text("Add Custom Action")
                .font(.headline)

            // Type picker
            Picker("Action Type", selection: $typeIndex) {
                Text("Web Search").tag(0)
                Text("Text Snippet").tag(1)
                Text("Shell Script").tag(2)
            }
            .pickerStyle(.segmented)

            // Title + Icon row
            HStack(spacing: 10) {
                TextField("Action Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                // Icon preview button — opens picker
                Button {
                    showingIconPicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: (try? iconName.isEmpty ? "wand.and.stars" : iconName) ?? "wand.and.stars")
                            .font(.system(size: 16))
                            .frame(width: 22, height: 22)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Choose icon")
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    IconPickerPopover(selectedIcon: $iconName)
                }
            }

            Divider()

            // Type-specific fields
            Group {
                if typeIndex == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL Template").font(.subheadline).fontWeight(.medium)
                        TextField("https://google.com/search?q={text}", text: $urlTemplate)
                            .textFieldStyle(.roundedBorder)
                        Text("Use **{text}** as a placeholder for the selected text.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else if typeIndex == 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Snippet Template").font(.subheadline).fontWeight(.medium)
                        TextField("e.g. **{text}**", text: $snippetTemplate)
                            .textFieldStyle(.roundedBorder)
                        Text("Use **{text}** as a placeholder for the selected text.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shell Script").font(.subheadline).fontWeight(.medium)
                        TextEditor(text: $shellScript)
                            .frame(height: 80)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                            )
                        Text("Use **$POPCLIP_TEXT** for the selected text.")
                            .font(.caption).foregroundColor(.secondary)
                        Toggle("Replace selection with output", isOn: $replaceSelection)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Action") { addAction() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
    
    private func addAction() {
        let actionType: CustomActionType
        switch typeIndex {
        case 0:  actionType = .webSearch(urlTemplate: urlTemplate)
        case 1:  actionType = .textSnippet(template: snippetTemplate)
        case 2:  actionType = .shellScript(script: shellScript, replaceSelection: replaceSelection)
        default: return
        }
        let newAction = CustomAction(
            id: "com.custom.\(UUID().uuidString.prefix(8))",
            title: title.trimmingCharacters(in: .whitespaces),
            iconName: iconName.isEmpty ? "wand.and.stars" : iconName,
            type: actionType
        )
        CustomActionManager.shared.register(customAction: newAction)
        dismiss()
    }
}

// MARK: - Icon Picker Popover

@MainActor
private struct IconPickerPopover: View {
    @Binding var selectedIcon: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredCategories: [(name: String, icons: [String])] {
        if searchText.isEmpty { return iconCategories }
        let q = searchText.lowercased()
        return iconCategories.compactMap { cat in
            let filtered = cat.icons.filter { $0.contains(q) }
            return filtered.isEmpty ? nil : (name: cat.name, icons: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search symbols…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredCategories, id: \.name) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 8), spacing: 4) {
                                ForEach(category.icons, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                        dismiss()
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 16))
                                            .frame(width: 34, height: 34)
                                            .background(
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .fill(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.06))
                                            )
                                            .foregroundColor(selectedIcon == icon ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(icon)
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .frame(width: 340, height: 320)
    }
}
