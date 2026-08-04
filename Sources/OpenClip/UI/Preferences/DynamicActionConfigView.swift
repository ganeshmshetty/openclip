// DynamicActionConfigView.swift
// OpenClip
//
// Dynamically constructs configuration form rows for extension options, reading and writing
// values through the injected option store (SettingsStore-backed in Phase 3; Keychain for
// secrets in Phase 7) instead of @AppStorage/UserDefaults.
import SwiftUI
import Core

@MainActor
public struct DynamicActionConfigView: View {
    let actionID: String
    let options: [ExtensionOption]
    let optionStore: any ActionOptionReading & ActionOptionWriting

    public init(
        actionID: String,
        options: [ExtensionOption],
        optionStore: any ActionOptionReading & ActionOptionWriting = SettingsActionOptionStore()
    ) {
        self.actionID = actionID
        self.options = options
        self.optionStore = optionStore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(options) { option in
                DynamicOptionRowView(actionID: actionID, option: option, optionStore: optionStore)
            }
        }
    }
}

@MainActor
struct DynamicOptionRowView: View {
    let actionID: String
    let option: ExtensionOption
    let optionStore: any ActionOptionReading & ActionOptionWriting

    @State private var storedValue: String

    init(
        actionID: String,
        option: ExtensionOption,
        optionStore: any ActionOptionReading & ActionOptionWriting
    ) {
        self.actionID = actionID
        self.option = option
        self.optionStore = optionStore
        _storedValue = State(initialValue: optionStore.stringValue(actionID: actionID, option: option))
    }

    private var binding: Binding<String> {
        Binding(
            get: { storedValue },
            set: { newValue in
                storedValue = newValue
                optionStore.setStringValue(newValue, actionID: actionID, option: option)
            }
        )
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
                    set: {
                        storedValue = $0 ? "true" : "false"
                        optionStore.setStringValue($0 ? "true" : "false", actionID: actionID, option: option)
                    }
                ))
                .toggleStyle(.switch)

            case .multiple:
                if let choices = option.options, !choices.isEmpty {
                    Picker(option.label, selection: binding) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    TextField(option.label, text: binding)
                        .textFieldStyle(.roundedBorder)
                }

            case .secret:
                SecureField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)

            case .string:
                TextField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
