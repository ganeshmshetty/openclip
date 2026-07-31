import Foundation
import ServiceManagement
import AppKit
import Core

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    public static let shared = LaunchAtLoginManager()
    
    @Published public var isEnabled: Bool {
        didSet {
            updateServiceStatus(isEnabled)
        }
    }
    
    private init() {
        if #available(macOS 13.0, *) {
            self.isEnabled = (SMAppService.mainApp.status == .enabled)
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: Constants.startAtLoginKey)
        }
    }
    
    public func syncStatus() {
        if #available(macOS 13.0, *) {
            let actualStatus = (SMAppService.mainApp.status == .enabled)
            if isEnabled != actualStatus {
                isEnabled = actualStatus
            }
        }
    }
    
    private func updateServiceStatus(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
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
                UserDefaults.standard.set(enabled, forKey: Constants.startAtLoginKey)
            } catch {
                print("SMAppService failed to update launch at login status: \(error)")
            }
        } else {
            UserDefaults.standard.set(enabled, forKey: Constants.startAtLoginKey)
        }
    }
}
