// ActionConfigSheet.swift
// OpenClip
//
// Renders configuration sheets for individual builtin action settings in preferences.
import SwiftUI
import Core

@MainActor
struct ActionConfigSheet: View {
    let configurationViewID: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configure Action")
                .font(.headline)
            
            if configurationViewID == "builtin.search" {
                SearchConfigView()
            } else if configurationViewID == "builtin.copy" {
                SimpleUseTextConfigView(key: "action.copy.useText", label: "Copy", iconDescription: "the document icon")
            } else if configurationViewID == "builtin.cut" {
                SimpleUseTextConfigView(key: "action.cut.useText", label: "Cut", iconDescription: "the scissors icon")
            } else if configurationViewID == "builtin.paste" {
                SimpleUseTextConfigView(key: "action.paste.useText", label: "Paste", iconDescription: "the clipboard icon")
            } else if configurationViewID == "builtin.calculate" {
                CalculateConfigView()
            } else if configurationViewID == "builtin.define" {
                SimpleUseTextConfigView(key: "action.define.useText", label: "Define", iconDescription: "the book icon")
            } else {
                Text("No configuration available for this action.")
                    .foregroundColor(.secondary)
            }
            
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(width: 350)
    }
}

private enum SearchEngineOption: String, CaseIterable, Identifiable {
    case google = "Google"
    case brave = "Brave Search"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case kagi = "Kagi"
    case perplexity = "Perplexity AI"
    case ecosia = "Ecosia"
    case custom = "Custom..."
    
    var id: String { rawValue }
    
    var urlTemplate: String {
        switch self {
        case .google: return "https://www.google.com/search?q={query}"
        case .brave: return "https://search.brave.com/search?q={query}"
        case .duckDuckGo: return "https://duckduckgo.com/?q={query}"
        case .bing: return "https://www.bing.com/search?q={query}"
        case .kagi: return "https://kagi.com/search?q={query}"
        case .perplexity: return "https://www.perplexity.ai/search?q={query}"
        case .ecosia: return "https://www.ecosia.org/search?q={query}"
        case .custom: return ""
        }
    }
}

private struct SearchConfigView: View {
    @AppStorage("action.search.url") private var searchURL: String = "https://www.google.com/search?q={query}"
    @State private var selectedEngine: SearchEngineOption = .google
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search Engine")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: $selectedEngine) {
                    ForEach(SearchEngineOption.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedEngine) { _, newEngine in
                    if newEngine != .custom {
                        searchURL = newEngine.urlTemplate
                    }
                }
            }
            
            if selectedEngine == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom URL Template")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. https://example.com/search?q={query}", text: $searchURL)
                        .textFieldStyle(.roundedBorder)
                    Text("Use {query} where the selected text should be inserted.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            if let matched = SearchEngineOption.allCases.first(where: { $0.urlTemplate == searchURL && $0 != .custom }) {
                selectedEngine = matched
            } else if searchURL.isEmpty || searchURL == "https://www.google.com/search?q={query}" {
                selectedEngine = .google
            } else {
                selectedEngine = .custom
            }
        }
    }
}

private struct SimpleUseTextConfigView: View {
    let key: String
    let label: String
    let iconDescription: String
    @AppStorage private var useText: Bool

    init(key: String, label: String, iconDescription: String) {
        self.key = key
        self.label = label
        self.iconDescription = iconDescription
        self._useText = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use text label ('\(label)') instead of icon", isOn: $useText)
                .font(.subheadline)
            Text("When enabled, the popup will show '\(label)' instead of \(iconDescription).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct CalculateConfigView: View {
    @AppStorage("action.calculate.mode") private var mode: String = "paste"
    @AppStorage("action.calculate.useText") private var useText: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Result Action")
                    .font(.subheadline)
                    .bold()
                
                Picker("", selection: $mode) {
                    Text("Paste Result").tag("paste")
                    Text("Copy to Clipboard Only").tag("copy")
                    Text("Append Result (e.g. 2+2 = 4)").tag("append")
                }
                .pickerStyle(.radioGroup)
            }
            
            Divider()
            
            Toggle("Use text label (=) instead of icon", isOn: $useText)
                .font(.subheadline)
            Text("When enabled, the popup will show '=' instead of the equal circle icon.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
