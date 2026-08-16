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
    @State private var primaryBehavior: String
    @State private var secondaryBehavior: String
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @ObservedObject private var permissionManager = PermissionManager.shared

    init() {
        _isAppEnabled = State(initialValue: DefaultSettingsStore.shared.get(.isAppEnabled))
        _primaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.primaryClickBehavior))
        _secondaryBehavior = State(initialValue: DefaultSettingsStore.shared.get(.secondaryClickBehavior))
    }
    
    var body: some View {
        Form {
            Section(header: Text("General Controls")) {
                // Row 1: Enable OpenClip
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "power")
                            .font(.system(size: 16))
                            .foregroundColor(isAppEnabled ? .accentColor : .secondary)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable OpenClip")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(isAppEnabled ? "Active & monitoring text selection" : "OpenClip is paused")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $isAppEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Enable OpenClip")
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
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trigger Popup Shortcut")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Global hotkey to manually trigger OpenClip HUD")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
                .padding(.vertical, 4)
                
                // Row 3: Start at Login
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                            .frame(width: 22, alignment: .center)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start at Login")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Launch OpenClip automatically when logging in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: $launchManager.isEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Start at Login")
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("When an action returns text")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Primary click")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("What happens to returned text on a primary click")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Secondary click")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("What happens to returned text on a right-click or ⇧-click")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility Access")
                                .font(.body)
                                .fontWeight(.medium)
                            Text(permissionManager.isAccessibilityGranted ? "Active permission for text detection" : "Required to detect selected text in apps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
