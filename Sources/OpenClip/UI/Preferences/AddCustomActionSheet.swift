import SwiftUI
import Core

@MainActor
public struct AddCustomActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var typeIndex = 0
    @State private var title = ""
    @State private var iconName = "wand.and.stars"
    @State private var displayPreference = 0 // 0 = Icon, 1 = Text
    @State private var showingIconPicker = false
    
    // Web Search
    @State private var urlTemplate = "https://google.com/search?q={text}"
    
    // Text Snippet
    @State private var snippetTemplate = "**{text}**"
    
    // Shell Script
    @State private var shellScript = "echo \"$OPENCLIP_TEXT\" | tr '[:lower:]' '[:upper:]'"
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
                TextField("Action Title / Text", text: $title)
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

            // Display preference picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Display Preference")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $displayPreference) {
                    Text("Icon").tag(0)
                    Text("Text").tag(1)
                }
                .pickerStyle(.segmented)
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
                        Text("Use **$OPENCLIP_TEXT** for the selected text.")
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
        let actionTitle = title.trimmingCharacters(in: .whitespaces)
        let newAction = CustomAction(
            id: "com.custom.\(UUID().uuidString.prefix(8))",
            title: actionTitle,
            iconName: iconName.isEmpty ? "wand.and.stars" : iconName,
            type: actionType
        )
        CustomActionManager.shared.register(customAction: newAction)
        
        if displayPreference == 1 {
            ActionCustomizationManager.shared.setOverride(
                for: newAction.id,
                title: actionTitle,
                symbol: nil,
                text: actionTitle
            )
        }
        
        dismiss()
    }
}

// MARK: - Icon Picker Popover@MainActor
struct IconPickerPopover: View {
    @Binding var selectedIcon: String
    @StateObject private var provider = UnifiedIconProvider.shared
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var displayedIcons: [IconEntry] {
        return provider.search(query: searchText, limit: 160)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Unified Search bar — searches ALL libraries at once in one place
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search \(provider.allIcons.count)+ icons (SF Symbols, FA, Lucide, Material)…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            Divider()

            if !provider.isLoaded {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Loading all icon libraries…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 8), spacing: 4) {
                        ForEach(displayedIcons) { item in
                            Button {
                                selectedIcon = item.id
                                dismiss()
                            } label: {
                                RenderIconView(iconStr: item.id)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(selectedIcon == item.id ? Color.accentColor : Color.primary.opacity(0.06))
                                    )
                                    .foregroundColor(selectedIcon == item.id ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .help("\(item.id) (\(item.library))")
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 360, height: 340)
    }
}
