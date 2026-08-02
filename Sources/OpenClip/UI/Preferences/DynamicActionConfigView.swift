// DynamicActionConfigView.swift
// OpenClip
//
// Dynamically constructs configuration form rows for extension options using SettingKey definitions via the Settings Door.
import SwiftUI
import Core

@MainActor
public struct DynamicActionConfigView: View {
    let actionID: String
    let options: [ExtensionOption]
    
    public init(actionID: String, options: [ExtensionOption]) {
        self.actionID = actionID
        self.options = options
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(options) { option in
                DynamicOptionRowView(actionID: actionID, option: option)
            }
        }
    }
}

@MainActor
struct DynamicOptionRowView: View {
    let actionID: String
    let option: ExtensionOption
    
    @AppStorage private var storedValue: String
    
    init(actionID: String, option: ExtensionOption) {
        self.actionID = actionID
        self.option = option
        let key = "action.\(actionID).option.\(option.identifier)"
        self._storedValue = AppStorage(wrappedValue: option.defaultValue ?? "", key)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(option.label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            switch option.type {
            case .boolean:
                Toggle(option.label, isOn: Binding(
                    get: { storedValue == "true" },
                    set: { storedValue = $0 ? "true" : "false" }
                ))
                .toggleStyle(.switch)
                
            case .multiple:
                if let choices = option.options, !choices.isEmpty {
                    Picker(option.label, selection: $storedValue) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    TextField(option.label, text: $storedValue)
                        .textFieldStyle(.roundedBorder)
                }
                
            case .secret:
                SecureField(option.label, text: $storedValue)
                    .textFieldStyle(.roundedBorder)
                
            case .string:
                TextField(option.label, text: $storedValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
