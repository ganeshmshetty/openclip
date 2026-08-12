// LaunchAtLoginManager.swift
// OpenClip
//
// Manages macOS login item registration using ServiceManagement SMAppService APIs.
// Persisted state goes through `SettingKey.startAtLogin` via the settings store — never raw
// `UserDefaults`. (Deployment target is macOS 14, so the pre-13 fallbacks are dead and dropped.)
import Foundation
import ServiceManagement
import AppKit
import Core

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public var isEnabled: Bool {
        didSet {
            apply(isEnabled)
        }
    }
    
    /// Injectable login-item updater. The default registers/unregisters via SMAppService; tests
    /// inject a recording no-op so toggling never touches the real login-items registry. Assigned
    /// before `isEnabled` (whose `didSet` calls it) — the observer does not fire during init.
    private let apply: (Bool) -> Void

    private init() {
        self.apply = LaunchAtLoginManager.updateServiceStatus
        self.isEnabled = LaunchAtLoginManager.readCurrentStatus()
    }

    internal init(apply: @escaping (Bool) -> Void) {
        self.apply = apply
        self.isEnabled = LaunchAtLoginManager.readCurrentStatus()
    }
    
    public func syncStatus() {
        let actualStatus = (SMAppService.mainApp.status == .enabled)
        if isEnabled != actualStatus {
            isEnabled = actualStatus
        }
    }
    
    private static func readCurrentStatus() -> Bool {
        (SMAppService.mainApp.status == .enabled)
    }

    private static func updateServiceStatus(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            DefaultSettingsStore.shared.set(.startAtLogin, value: enabled)
        } catch {
            Log.settings.error("SMAppService failed to update launch at login status: \(error.localizedDescription)")
        }
    }
}
