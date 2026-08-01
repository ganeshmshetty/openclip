import SwiftUI
import Core

@MainActor
struct ActionConfigSheet: View {
    let actionID: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Configure Action")
                .font(.headline)
            
            if actionID == "builtin.search" {
                SearchConfigView()
            } else if actionID == "builtin.copy" {
                CopyConfigView()
            } else if actionID == "builtin.cut" {
                CutConfigView()
            } else if actionID == "builtin.paste" {
                PasteConfigView()
            } else if actionID == "builtin.calculate" {
                CalculateConfigView()
            } else if actionID == "builtin.define" {
                DefineConfigView()
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

private struct SearchConfigView: View {
    @AppStorage("action.search.url") private var searchURL: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search URL Template")
                .font(.subheadline)
            TextField("e.g., https://search.brave.com/search?q={query}", text: $searchURL)
                .textFieldStyle(.roundedBorder)
            Text("Use {query} where the selected text should be inserted. Leave empty to use Google by default.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct CopyConfigView: View {
    @AppStorage("action.copy.useText") private var useText: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use text label instead of icon", isOn: $useText)
            Text("When enabled, the popup will show 'Copy' instead of the document icon.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct PasteConfigView: View {
    @AppStorage("action.paste.useText") private var useText: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use text label instead of icon", isOn: $useText)
            Text("When enabled, the popup will show 'Paste' instead of the clipboard icon.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct CutConfigView: View {
    @AppStorage("action.cut.useText") private var useText: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use text label instead of icon", isOn: $useText)
            Text("When enabled, the popup will show 'Cut' instead of the scissors icon.")
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

private struct DefineConfigView: View {
    @AppStorage("action.define.useText") private var useText: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use text label ('Define') instead of icon", isOn: $useText)
                .font(.subheadline)
            Text("When enabled, the popup will show 'Define' instead of the book icon.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
