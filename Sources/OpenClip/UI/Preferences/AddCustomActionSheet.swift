import SwiftUI
import Core

@MainActor
public struct AddCustomActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var typeIndex = 0
    @State private var title = ""
    @State private var iconName = "wand.and.stars"
    
    // Web Search
    @State private var urlTemplate = "https://github.com/search?q={text}"
    
    // Text Snippet
    @State private var snippetTemplate = "**{text}**"
    
    // Shell Script
    @State private var shellScript = "echo \"$POPCLIP_TEXT\" | tr '[:lower:]' '[:upper:]'"
    @State private var replaceSelection = false
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Action").font(.headline)
            
            Picker("Action Type", selection: $typeIndex) {
                Text("Web Search").tag(0)
                Text("Text Snippet").tag(1)
                Text("Shell Script").tag(2)
            }
            .pickerStyle(.segmented)
            
            TextField("Title", text: $title)
            
            HStack {
                TextField("Icon (SF Symbol)", text: $iconName)
                Image(systemName: iconName)
                    .frame(width: 20)
            }
            
            Divider()
            
            if typeIndex == 0 {
                VStack(alignment: .leading) {
                    Text("URL Template").font(.subheadline)
                    TextField("e.g. https://github.com/search?q={text}", text: $urlTemplate)
                    Text("Use {text} for the selected text.").font(.caption).foregroundColor(.secondary)
                }
            } else if typeIndex == 1 {
                VStack(alignment: .leading) {
                    Text("Snippet Template").font(.subheadline)
                    TextField("e.g. **{text}**", text: $snippetTemplate)
                    Text("Use {text} for the selected text.").font(.caption).foregroundColor(.secondary)
                }
            } else if typeIndex == 2 {
                VStack(alignment: .leading) {
                    Text("Shell Script").font(.subheadline)
                    TextEditor(text: $shellScript)
                        .frame(height: 80)
                        .font(.system(.body, design: .monospaced))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5)))
                    Text("Use $POPCLIP_TEXT for the selected text.").font(.caption).foregroundColor(.secondary)
                    
                    Toggle("Replace Selection", isOn: $replaceSelection)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add Action") {
                    addAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
    }
    
    private func addAction() {
        let actionType: CustomActionType
        switch typeIndex {
        case 0:
            actionType = .webSearch(urlTemplate: urlTemplate)
        case 1:
            actionType = .textSnippet(template: snippetTemplate)
        case 2:
            actionType = .shellScript(script: shellScript, replaceSelection: replaceSelection)
        default:
            return
        }
        
        let newAction = CustomAction(
            id: "com.custom.\(UUID().uuidString.prefix(8))",
            title: title,
            iconName: iconName,
            type: actionType
        )
        
        CustomActionManager.shared.register(customAction: newAction)
        dismiss()
    }
}
