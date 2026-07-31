import AppKit
import ApplicationServices

/// Centralized manager for macOS system accessibility permissions.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    @Published public private(set) var isAccessibilityGranted: Bool = false
    
    private var checkTimer: Timer?
    
    private init() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }
    
    /// Starts periodic checking of accessibility status.
    public func startMonitoring(interval: TimeInterval = 0.8) {
        checkStatus()
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStatus()
            }
        }
    }
    
    /// Stops periodic checking.
    public func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    /// Re-evaluates accessibility trust status.
    public func checkStatus() {
        let current = AXIsProcessTrusted()
        if isAccessibilityGranted != current {
            isAccessibilityGranted = current
        }
    }
    
    /// Prompts macOS native permission dialog and opens System Settings directly to Accessibility.
    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
