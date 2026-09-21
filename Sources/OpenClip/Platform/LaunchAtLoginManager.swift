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
            self.requiresApproval = LaunchAtLoginManager.readRequiresApproval()
        }
    }
    
    @Published public var requiresApproval: Bool
    
    /// Injectable login-item updater. The default registers/unregisters via SMAppService; tests
    /// inject a recording no-op so toggling never touches the real login-items registry. Assigned
    /// before `isEnabled` (whose `didSet` calls it) — the observer does not fire during init.
    private let apply: (Bool) -> Void

    private init() {
        self.apply = LaunchAtLoginManager.updateServiceStatus
        self.requiresApproval = LaunchAtLoginManager.readRequiresApproval()
        self.isEnabled = LaunchAtLoginManager.readCurrentStatus()
    }

    internal init(apply: @escaping (Bool) -> Void,
                  initialStatus: Bool = LaunchAtLoginManager.readCurrentStatus(),
                  requiresApproval: Bool = LaunchAtLoginManager.readRequiresApproval()) {
        self.apply = apply
        self.requiresApproval = requiresApproval
        self.isEnabled = initialStatus
    }
    
    public func syncStatus() {
        #if !DEBUG
        let status = SMAppService.mainApp.status
        let actualStatus = (status == .enabled || status == .requiresApproval)
        let actualRequiresApproval = (status == .requiresApproval)
        if isEnabled != actualStatus {
            isEnabled = actualStatus
        }
        if requiresApproval != actualRequiresApproval {
            requiresApproval = actualRequiresApproval
        }
        #else
        let saved = DefaultSettingsStore.shared.get(.startAtLogin)
        if isEnabled != saved {
            isEnabled = saved
        }
        #endif
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
    
    private static func readCurrentStatus() -> Bool {
        #if !DEBUG
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
        #else
        return DefaultSettingsStore.shared.get(.startAtLogin)
        #endif
    }

    private static func readRequiresApproval() -> Bool {
        #if !DEBUG
        return SMAppService.mainApp.status == .requiresApproval
        #else
        return false
        #endif
    }

    private static func updateServiceStatus(_ enabled: Bool) {
        #if !DEBUG
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            DefaultSettingsStore.shared.set(.startAtLogin, value: enabled)
        } catch {
            Log.settings.error("SMAppService failed to update launch at login status: \(error.localizedDescription)")
        }
        #else
        DefaultSettingsStore.shared.set(.startAtLogin, value: enabled)
        Log.settings.info("DEBUG build: simulated SMAppService update to \(enabled)")
        #endif
    }
}
