import SwiftUI
import AppKit
import Core

@MainActor
public struct EditActionSheet: View {
    let action: any Action
    @Environment(\.dismiss) private var dismiss
    
    @State private var customTitle: String = ""
    @State private var iconType: Int = 0 // 0 = SF Symbol, 1 = Emoji / Text
    @State private var iconSymbol: String = ""
    @State private var iconText: String = ""
    
    // Custom Action State
    @State private var customType: CustomActionType = .textSnippet(template: "{text}")
    @State private var customURLTemplate: String = "https://www.google.com/search?q={text}"
    @State private var customSnippetTemplate: String = "{text}"
    @State private var customShellScript: String = "echo $POPCLIP_TEXT"
    @State private var replaceSelection: Bool = true
    
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
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Appearance Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appearance")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action Name")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            TextField("Display Name", text: $customTitle)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action Icon")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $iconType) {
                                Text("SF Symbol").tag(0)
                                Text("Emoji / Text").tag(1)
                            }
                            .pickerStyle(.segmented)
                            
                            if iconType == 0 {
                                TextField("Symbol Name (e.g. magnifyingglass)", text: $iconSymbol)
                                    .textFieldStyle(.roundedBorder)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                                    ForEach(popularSymbols, id: \.self) { sym in
                                        Button {
                                            iconSymbol = sym
                                        } label: {
                                            Image(systemName: sym)
                                                .font(.system(size: 14))
                                                .frame(width: 32, height: 32)
                                                .background(iconSymbol == sym ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 4)
                            } else {
                                TextField("Emoji or Text (e.g. Aa, 🔍, ⚡️)", text: $iconText)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        Button("Reset Name & Icon to Default") {
                            ActionCustomizationManager.shared.resetOverride(for: action.id)
                            loadInitialState()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                    
                    Divider()
                    
                    // Type-Specific Behavior Section
                    if action.id == "builtin.search" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Search Behavior")
                                .font(.headline)
                            BuiltinSearchConfigView()
                        }
                    } else if let customAction = action as? CustomAction {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Custom Action Logic")
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
        .frame(width: 400, height: 500)
        .onAppear {
            loadInitialState()
        }
    }
    
    private func loadInitialState() {
        let override = ActionCustomizationManager.shared.override(for: action.id)
        customTitle = override?.customTitle ?? action.title
        
        if let txt = override?.customIconText, !txt.isEmpty {
            iconType = 1
            iconText = txt
            iconSymbol = ""
        } else if let sym = override?.customIconSymbol, !sym.isEmpty {
            iconType = 0
            iconSymbol = sym
            iconText = ""
        } else {
            switch action.icon {
            case .symbol(let sym):
                iconType = 0
                iconSymbol = sym
            case .text(let txt):
                iconType = 1
                iconText = txt
            default:
                iconType = 0
                iconSymbol = "star"
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
        let titleOverride = (customTitle == action.title) ? nil : customTitle
        let symbolOverride = (iconType == 0 && !iconSymbol.isEmpty) ? iconSymbol : nil
        let textOverride = (iconType == 1 && !iconText.isEmpty) ? iconText : nil
        
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
