// DynamicActionConfigView.swift
// OpenClip
//
// Dynamically constructs configuration form rows for extension options, reading and writing
// values through the injected option store (KeychainActionOptionStore since Phase 7 — secrets
// route to Keychain, non-secrets to SettingsStore). Rows for required-but-unset options are
// highlighted with a red border + "Required" caption (surfaced via `missingOptionIDs`).
// Formatted with macOS Inset Grouped horizontal alignment (label on left, control on right).
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
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Divider()
                        .padding(.horizontal, 12)
                }
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
        if isSearchURLOption {
            SearchEngineURLOptionView(
                actionID: actionID,
                option: option,
                optionStore: optionStore,
                isMissing: isMissing
            )
        } else {
            standardRowBody
        }
    }

    /// The built-in Search action's `url` option gets the search-engine preset picker (Google /
    /// DuckDuckGo / Kagi / Brave / Bing / Ecosia / Custom) instead of a bare template text field.
    private var isSearchURLOption: Bool {
        actionID == SearchAction().id && option.identifier == "url"
    }

    private var standardRowBody: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(option.label)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if isMissing {
                    Text("Required")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 8)

            switch option.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { storedValue == "true" },
                    set: {
                        storedValue = $0 ? "true" : "false"
                        optionStore.setStringValue($0 ? "true" : "false", actionID: actionID, option: option)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .missingFieldHighlight(isMissing)

            case .multiple:
                if let choices = option.options, !choices.isEmpty {
                    Picker("", selection: binding) {
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
                        .frame(maxWidth: 200)
                        .missingFieldHighlight(isMissing)
                }

            case .secret:
                SecureField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .missingFieldHighlight(isMissing)

            case .string:
                TextField(option.label, text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .missingFieldHighlight(isMissing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func choiceDisplayLabel(_ choice: String) -> String {
        switch choice.lowercased() {
        case "native": return String(localized: "Native (Default .ics)")
        case "busycal": return "BusyCal"
        case "fantastical": return "Fantastical"
        case "apple": return String(localized: "Apple Calendar")
        case "google": return String(localized: "Google Calendar")
        default: return choice.capitalized
        }
    }
}

/// Renders the built-in Search action's URL option as a search-engine preset picker. Provides
/// one-click selection among curated presets (Google / DuckDuckGo / Kagi / Brave / Bing / Ecosia)
/// while keeping a raw `{query}` template field reachable through the trailing "Custom..." choice.
/// Every write still routes through the injected option store (SettingsStore-backed), so the stored
/// `action.builtin.search.option.url` value remains the single source of truth; a stored template
/// that matches no preset simply shows the picker on "Custom..." with the template in the field.
@MainActor
private struct SearchEngineURLOptionView: View {
    let actionID: String
    let option: ExtensionOption
    let optionStore: any ActionOptionReading & ActionOptionWriting
    var isMissing: Bool

    private enum SearchEngineSelection: Hashable {
        case preset(String) // stable preset id
        case custom
    }

    @State private var selection: SearchEngineSelection
    @State private var customTemplate: String

    init(
        actionID: String,
        option: ExtensionOption,
        optionStore: any ActionOptionReading & ActionOptionWriting,
        isMissing: Bool
    ) {
        self.actionID = actionID
        self.option = option
        self.optionStore = optionStore
        self.isMissing = isMissing
        let stored = optionStore.stringValue(actionID: actionID, option: option)
        _selection = State(initialValue: Self.initialSelection(for: stored))
        _customTemplate = State(initialValue: stored)
    }

    /// Preset when the stored template matches exactly; otherwise Custom (covers self-hosted or
    /// hand-edited endpoints, which are never silently snapped back to a preset).
    private static func initialSelection(for stored: String) -> SearchEngineSelection {
        SearchEnginePreset.preset(matching: stored).map { .preset($0.id) } ?? .custom
    }

    private var pickerBinding: Binding<SearchEngineSelection> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                if case .preset(let presetID) = newValue, let preset = SearchEnginePreset.preset(id: presetID) {
                    customTemplate = preset.urlTemplate
                    optionStore.setStringValue(preset.urlTemplate, actionID: actionID, option: option)
                }
            }
        )
    }

    private var customTemplateBinding: Binding<String> {
        Binding(
            get: { customTemplate },
            set: { newValue in
                customTemplate = newValue
                optionStore.setStringValue(newValue, actionID: actionID, option: option)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(option.label)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    if isMissing {
                        Text("Required")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }

                Spacer(minLength: 8)

                Picker("", selection: pickerBinding) {
                    ForEach(SearchEnginePreset.all) { preset in
                        Text(preset.displayName).tag(SearchEngineSelection.preset(preset.id))
                    }
                    Text(String(localized: "Custom...")).tag(SearchEngineSelection.custom)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 200)
                .missingFieldHighlight(isMissing)
            }

            if selection == .custom {
                TextField("https://example.com/search?q={query}", text: customTemplateBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .missingFieldHighlight(isMissing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
