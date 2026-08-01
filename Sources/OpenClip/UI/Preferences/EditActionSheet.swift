import SwiftUI
import AppKit
import Core

@MainActor
public struct EditActionSheet: View {
    let action: any Action
    @Environment(\.dismiss) private var dismiss
    
    @State private var activeTab: Int = 0 // 0 = Appearance, 1 = General
    @State private var customTitle: String = ""
    @State private var iconType: Int = 0 // 0 = SF Symbol, 1 = Emoji / Text
    @State private var iconSymbol: String = ""
    @State private var iconText: String = ""
    @State private var showingIconPicker: Bool = false
    
    // Custom Action State
    @State private var customType: CustomActionType = .textSnippet(template: "{text}")
    @State private var customURLTemplate: String = "https://www.google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "{text}"
    @State private var customShellScript: String = "echo $OPENCLIP_TEXT"
    @State private var replaceSelection: Bool = true
    @AppStorage("completionCopyToClipboard") private var completionCopyToClipboard: Bool = false
    
    private let popularSymbols = [
        "magnifyingglass", "doc.on.doc", "scissors", "folder",
        "sparkles", "link", "character.cursor", "square.and.arrow.up",
        "textformat", "globe", "terminal", "gearshape"
    ]
    
    public init(action: any Action) {
        self.action = action
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Action")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Picker("", selection: $activeTab) {
                Label("Appearance", systemImage: "paintpalette").tag(0)
                Label("General", systemImage: "gearshape").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if activeTab == 0 {
                        // Appearance Tab
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Action Name / Text")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 10) {
                                    TextField("Display Name or Emoji", text: $customTitle)
                                        .textFieldStyle(.roundedBorder)

                                    Button {
                                        showingIconPicker.toggle()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: iconSymbol.isEmpty ? "star" : iconSymbol)
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
                                        IconPickerPopover(selectedIcon: $iconSymbol)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            // 3. Selection at bottom for display preference
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Display Preference")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $iconType) {
                                    Text("Icon").tag(0)
                                    Text("Text").tag(1)
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            Button("Reset Name & Icon to Default") {
                                ActionCustomizationManager.shared.resetOverride(for: action.id)
                                loadInitialState()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                            .padding(.top, 4)
                        }
                    } else {
                        // General Tab (Behavior & Logic)
                        if !action.actionOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Action Options")
                                    .font(.headline)
                                DynamicActionConfigView(actionID: action.id, options: action.actionOptions)
                            }
                        } else if let customAction = action as? CustomAction {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Action Type & Execution Logic")
                                    .font(.headline)
                                
                                Picker("Type", selection: $customType) {
                                    Text("Web Search").tag(CustomActionType.webSearch(urlTemplate: customURLTemplate))
                                    Text("Text Snippet").tag(CustomActionType.textSnippet(template: customSnippetTemplate))
                                    Text("Shell Script").tag(CustomActionType.shellScript(script: customShellScript, replaceSelection: replaceSelection))
                                }
                                .pickerStyle(.segmented)
                                
                                switch customType {
                                case .webSearch:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("URL Template").font(.caption).foregroundColor(.secondary)
                                        TextField("https://example.com/search?q={text}", text: $customURLTemplate)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                case .textSnippet:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Snippet Template").font(.caption).foregroundColor(.secondary)
                                        TextEditor(text: $customSnippetTemplate)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 70)
                                            .border(Color.secondary.opacity(0.2))
                                    }
                                case .shellScript:
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Shell Script (Zsh)").font(.caption).foregroundColor(.secondary)
                                        TextEditor(text: $customShellScript)
                                            .font(.system(.body, design: .monospaced))
                                            .frame(height: 90)
                                            .border(Color.secondary.opacity(0.2))
                                        
                                        Toggle("Replace selected text with output", isOn: $replaceSelection)
                                            .font(.caption)
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("General Action Information")
                                    .font(.headline)
                                Text("Standard action. Execution behavior and options are managed automatically by OpenClip.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // Footer Action Buttons
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Changes") {
                    saveChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 340, height: 360)
        .onAppear {
            loadInitialState()
        }
    }
    
    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)
        
        if let txt = override?.customIconText, !txt.isEmpty {
            iconType = 1
            customTitle = txt
        } else {
            customTitle = override?.customTitle ?? action.title
            if let sym = override?.customIconSymbol, !sym.isEmpty {
                iconType = 0
                iconSymbol = sym
            } else {
                switch action.icon {
                case .symbol(let sym):
                    iconType = 0
                    iconSymbol = sym
                case .text(let txt):
                    iconType = 1
                    customTitle = txt
                default:
                    iconType = 0
                    iconSymbol = "star"
                }
            }
        }
        
        if let customAction = action as? CustomAction {
            customType = customAction.type
            switch customAction.type {
            case .webSearch(let url): customURLTemplate = url
            case .textSnippet(let snippet): customSnippetTemplate = snippet
            case .shellScript(let script, let replace):
                customShellScript = script
                replaceSelection = replace
            }
        }
    }
    
    private func saveChanges() {
        // Save appearance overrides
        let titleOverride: String?
        let symbolOverride: String?
        let textOverride: String?
        
        if iconType == 1 {
            // Text / Emoji Display Preference: customTitle is both title and text icon
            textOverride = customTitle.isEmpty ? nil : customTitle
            titleOverride = customTitle.isEmpty ? nil : customTitle
            symbolOverride = nil
        } else {
            // SF Symbol Preference: Action Name + SF Symbol
            titleOverride = (customTitle == action.title) ? nil : customTitle
            symbolOverride = iconSymbol.isEmpty ? nil : iconSymbol
            textOverride = nil
        }
        
        ActionCustomizationManager.shared.setOverride(
            for: action.id,
            title: titleOverride,
            symbol: symbolOverride,
            text: textOverride
        )
        
        // Save custom action logic if applicable
        if action is CustomAction {
            let finalType: CustomActionType
            switch iconType { // reusing switch structure for custom type saving
            default:
                if case .webSearch = customType {
                    finalType = .webSearch(urlTemplate: customURLTemplate)
                } else if case .textSnippet = customType {
                    finalType = .textSnippet(template: customSnippetTemplate)
                } else {
                    finalType = .shellScript(script: customShellScript, replaceSelection: replaceSelection)
                }
            }
            
            let updatedCustomAction = CustomAction(
                id: action.id,
                title: action.displayTitle,
                iconName: iconSymbol.isEmpty ? "star" : iconSymbol,
                type: finalType
            )
            CustomActionManager.shared.register(customAction: updatedCustomAction)
        }
    }
}

private struct BuiltinSearchConfigView: View {
    @AppStorage("action.search.url") private var searchURL: String = "https://www.google.com/search?q={query}"
    @State private var selectedEngine: String = "Google"
    
    private let engines: [(name: String, template: String)] = [
        ("Google", "https://www.google.com/search?q={query}"),
        ("Brave Search", "https://search.brave.com/search?q={query}"),
        ("DuckDuckGo", "https://duckduckgo.com/?q={query}"),
        ("Bing", "https://www.bing.com/search?q={query}"),
        ("Kagi", "https://kagi.com/search?q={query}"),
        ("Perplexity AI", "https://www.perplexity.ai/search?q={query}"),
        ("Ecosia", "https://www.ecosia.org/search?q={query}"),
        ("Custom...", "")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Search Engine", selection: $selectedEngine) {
                ForEach(engines, id: \.name) { engine in
                    Text(engine.name).tag(engine.name)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedEngine) { _, newName in
                if let matched = engines.first(where: { $0.name == newName }), !matched.template.isEmpty {
                    searchURL = matched.template
                }
            }
            
            if selectedEngine == "Custom..." {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom URL Template").font(.caption).foregroundColor(.secondary)
                    TextField("e.g. https://example.com/search?q={query}", text: $searchURL)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onAppear {
            if let matched = engines.first(where: { $0.template == searchURL && !$0.template.isEmpty }) {
                selectedEngine = matched.name
            } else {
                selectedEngine = "Custom..."
            }
        }
    }
}

struct BuiltinCalendarConfigView: View {
    @AppStorage("action.calendar.provider") private var calendarProvider: String = "native"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Target Calendar", selection: $calendarProvider) {
                Text("Native macOS Calendar App").tag("native")
                Text("Google Calendar (Web Browser)").tag("google")
            }
            .pickerStyle(.menu)

            Text(calendarProvider == "google"
                 ? "Opens prefilled event creation in Google Calendar in your web browser."
                 : "Opens native macOS Calendar app event creation dialog directly on your Mac.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
