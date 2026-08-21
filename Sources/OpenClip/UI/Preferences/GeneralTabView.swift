// GeneralTabView.swift
// OpenClip
//
// The General preferences tab: app enable toggle, trigger hotkey, start-at-login,
// and system-permission status. Split out of PreferencesView.swift.
import SwiftUI
import Core
import KeyboardShortcuts

@MainActor
struct GeneralTab: View {
    /// Backed by the settings store — the single owner of `isAppEnabled`. Seeded at init and kept
    /// in sync with external changes (status-bar toggle) via the shared state-changed notification.
    @State private var isAppEnabled: Bool
    @State private var isMouseHoldEnabled: Bool
    @State private var primaryBehavior: String
    @State private var secondaryBehavior: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _isMouseHoldEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isMouseHoldEnabled))
        _primaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.primaryClickBehavior))
        _secondaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.secondaryClickBehavior))
    }
    
    var body: some View {
        Form {
            Section(header: Text("General Controls")) {
                // Row 1: Appear Automatically
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "cursorarrow")
                            .font(.system(size: 16))
                            .foregroundColor(isAppEnabled ? .accentColor : .secondary)
                            .frame(width: 22, alignment: .center)
                        
                        Text("Appear Automatically")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Toggle("", isOn: $isAppEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Appear Automatically")
                        .onChange(of: isAppEnabled) { _, newValue in
                            DefaultSettingsStore.shared.set(.isAppEnabled, value: newValue)
                            NotificationCenter.default.post(name: Notification.Name("OpenClipEnabledStateChanged"), object: newValue)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenClipEnabledStateChanged"))) { notification in
                            isAppEnabled = (notification.object as? Bool) ?? DefaultSettingsStore.shared.get(.isAppEnabled)
                        }
                }
                .padding(.vertical, 4)
                
                // Row 2: Trigger Shortcut
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 22, alignment: .center)
                        
                        Text("Trigger Popup Shortcut")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
                .padding(.vertical, 4)

                // Row 3: Hold Mouse to Trigger
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 16))
                            .foregroundColor(isMouseHoldEnabled ? .accentColor : .secondary)
                            .frame(width: 22, alignment: .center)
                        
                        Text("Hold Mouse to Trigger")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Toggle("", isOn: $isMouseHoldEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Hold Mouse to Trigger")
                        .onChange(of: isMouseHoldEnabled) { _, newValue in
                            DefaultSettingsStore.shared.set(.isMouseHoldEnabled, value: newValue)
                        }
                }
                .padding(.vertical, 4)
                
                // Row 3: Start at Login
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 22, alignment: .center)
                        
                        Text("Start at Login")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Spacer()
                    Toggle("", isOn: $launchManager.isEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Start at Login")
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Action Results")) {
                HStack {
                    Text("Primary click")
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    Picker("Primary click", selection: $primaryBehavior) {
                        ForEach(ResultDeliveryPreference.allCases, id: \.self) { pref in
                            Text(pref.rawValue.capitalized).tag(pref.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: primaryBehavior) { _, newValue in
                        DefaultSettingsStore.shared.set(.primaryClickBehavior, value: newValue)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Secondary click")
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    Picker("Secondary click", selection: $secondaryBehavior) {
                        ForEach(ResultDeliveryPreference.allCases, id: \.self) { pref in
                            Text(pref.rawValue.capitalized).tag(pref.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: secondaryBehavior) { _, newValue in
                        DefaultSettingsStore.shared.set(.secondaryClickBehavior, value: newValue)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("System Permissions")) {
                // Row 4: Accessibility Access
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16))
                            .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                            .frame(width: 22, alignment: .center)
                        
                        Text("Accessibility Access")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Image(systemName: permissionManager.isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text(permissionManager.isAccessibilityGranted ? "Granted" : "Required")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(permissionManager.isAccessibilityGranted ? .green : .orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((permissionManager.isAccessibilityGranted ? Color.green : Color.orange).opacity(0.15))
                        )
                        
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear { permissionManager.startMonitoring() }
        .onDisappear { permissionManager.stopMonitoring() }
    }
}
