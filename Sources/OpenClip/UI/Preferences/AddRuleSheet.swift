import SwiftUI
import AppKit
import Core

@MainActor
public struct AddRuleSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAppBundleID: String = ""
    @State private var customBundleID: String = ""
    @State private var useCustomBundleID: Bool = false

    @State private var disableOpenClip: Bool = false
    @State private var denyFormatting: Bool = false
    @State private var grabPasteboard: Bool = false
    @State private var assumePaste: Bool = false

    private var runningApps: [(name: String, bundleID: String, icon: NSImage)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app -> (String, String, NSImage)? in
                guard let id = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? id
                let icon = app.icon ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
                return (name, id, icon)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    public init() {}

    private var effectiveBundleID: String {
        useCustomBundleID ? customBundleID.trimmingCharacters(in: .whitespaces) : selectedAppBundleID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add App Rule")
                .font(.headline)

            // Application Selection Card
            VStack(alignment: .leading, spacing: 10) {
                Text("Target Application").font(.subheadline).fontWeight(.medium)

                Toggle("Enter custom Bundle ID or Wildcard (e.g. com.adobe.*)", isOn: $useCustomBundleID)
                    .font(.caption)

                if useCustomBundleID {
                    TextField("e.g. com.figma.Desktop or com.jetbrains.*", text: $customBundleID)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Running Application", selection: $selectedAppBundleID) {
                        Text("Select an active application…").tag("")
                        ForEach(runningApps, id: \.bundleID) { app in
                            Text("\(app.name) (\(app.bundleID))").tag(app.bundleID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            Divider()

            // Policy Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Rule Behaviors").font(.subheadline).fontWeight(.medium)

                Toggle(isOn: $disableOpenClip) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("🛑 Disable OpenClip completely in this app")
                            .font(.system(size: 13, weight: .medium))
                        Text("Popup will never appear when selecting text in this application.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $denyFormatting) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("📝 Hide Formatting actions")
                            .font(.system(size: 13, weight: .medium))
                        Text("Hides Markdown & formatting tools when selecting text in code editors or IDEs.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $grabPasteboard) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("📋 Force Clipboard mode (Cmd+C)")
                            .font(.system(size: 13, weight: .medium))
                        Text("Use for apps that block macOS Accessibility text selection (e.g. Obsidian, Skype).")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $assumePaste) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("📌 Force enable Paste button")
                            .font(.system(size: 13, weight: .medium))
                        Text("Always show Paste button even if the app doesn't declare text input focus.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") { addRule() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(effectiveBundleID.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear {
            if let firstApp = runningApps.first {
                selectedAppBundleID = firstApp.bundleID
            }
        }
    }

    private func addRule() {
        let id = effectiveBundleID
        guard !id.isEmpty else { return }

        let rule = AppRule(
            bundleIdentifiers: [id],
            denyFormatting: denyFormatting ? true : nil,
            denyProbe: disableOpenClip ? true : nil,
            grabPasteboard: grabPasteboard ? true : nil,
            assumePaste: assumePaste ? true : nil
        )

        RuleEngine.shared.addRule(rule)
        dismiss()
    }
}
