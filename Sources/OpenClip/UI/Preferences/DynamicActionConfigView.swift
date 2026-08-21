// DynamicActionConfigView.swift
// OpenClip
//
// Dynamically constructs configuration form rows for extension options, reading and writing
// values through the injected option store (KeychainActionOptionStore since Phase 7 — secrets
// route to Keychain, non-secrets to SettingsStore). Rows for required-but-unset options are
// highlighted with a red border + "Required" caption (surfaced via `missingOptionIDs`).
import SwiftUI
import Core

@MainActor
public struct DynamicActionConfigView: View {
    let actionID: String
    let options: [ExtensionOption]
    let optionStore: any ActionOptionReading & ActionOptionWriting
    var missingOptionIDs: Set<String> = []

    public init(
        actionID: String,
        options: [ExtensionOption],
        optionStore: any ActionOptionReading & ActionOptionWriting = SecretActionOptionStore(),
        missingOptionIDs: Set<String> = []
    ) {
        self.actionID = actionID
        self.options = options
        self.optionStore = optionStore
        self.missingOptionIDs = missingOptionIDs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(options) { option in
                DynamicOptionRowView(
                    actionID: actionID,
                    option: option,
                    optionStore: optionStore,
                    missingOptionIDs: missingOptionIDs
                )
            }
        }
    }
}

@MainActor
struct DynamicOptionRowView: View {
    let actionID: String
    let option: ExtensionOption
    let optionStore: any ActionOptionReading & ActionOptionWriting
    var missingOptionIDs: Set<String> = []

    @State private var storedValue: String

    init(
        actionID: String,
        option: ExtensionOption,
        optionStore: any ActionOptionReading & ActionOptionWriting,
        missingOptionIDs: Set<String> = []
    ) {
        self.actionID = actionID
        self.option = option
        self.optionStore = optionStore
        self.missingOptionIDs = missingOptionIDs
        _storedValue = State(initialValue: optionStore.stringValue(actionID: actionID, option: option))
    }

    private var isMissing: Bool { missingOptionIDs.contains(option.identifier) }

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
            HStack(spacing: 6) {
                Text(option.label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isMissing {
                    Text("Required")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }

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
                .missingFieldHighlight(isMissing)

            case .multiple:
                if let choices = option.options, !choices.isEmpty {
                    Picker(option.label, selection: binding) {
                        ForEach(choices, id: \.self) { choice in
                            Text(choiceDisplayLabel(choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .missingFieldHighlight(isMissing)
                } else {
                    TextField(option.label, text: binding)
                        .textFieldStyle(.roundedBorder)
                        .missingFieldHighlight(isMissing)
                }

            case .secret:
                SecureField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .missingFieldHighlight(isMissing)

            case .string:
                TextField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .missingFieldHighlight(isMissing)
            }
        }
    }

    private func choiceDisplayLabel(_ choice: String) -> String {
        switch choice.lowercased() {
        case "native": return "Native (Default .ics)"
        case "busycal": return "BusyCal"
        case "fantastical": return "Fantastical"
        case "apple": return "Apple Calendar"
        case "google": return "Google Calendar"
        default: return choice.capitalized
        }
    }
}

private extension View {
    /// Emphasizes a required-but-unset option field with a red rounded border. No-op when not missing.
    @ViewBuilder
    func missingFieldHighlight(_ isMissing: Bool) -> some View {
        if isMissing {
            self
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.red.opacity(0.7), lineWidth: 1)
                )
        } else {
            self
        }
    }
}
