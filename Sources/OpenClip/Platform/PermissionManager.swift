// PermissionManager.swift
// OpenClip
//
// Checks and prompts for required macOS Accessibility permissions necessary for text retrieval and event monitoring.
import AppKit
import ApplicationServices
import Core

/// Centralized manager for macOS system accessibility permissions.
/// Uses a continuous async polling loop (not Timer) to reliably detect
/// AXIsProcessTrusted changes on the main actor.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false

    private var pollingTask: Task<Void, Never>?

    private init() {
        self.isAccessibilityGranted = Self.queryAX()
    }

    // MARK: - Public API

    /// Start continuously polling AX status every 0.5 s.
    public func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.checkStatus()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            }
        }
    }

    /// Stop polling.
    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Single manual check — useful for the "Re-check" button.
    public func checkStatus() {
        let current = Self.queryAX()
        if isAccessibilityGranted != current {
            isAccessibilityGranted = current
        }
    }

    /// Open System Settings → Accessibility and prompt macOS TCC to evaluate the running binary.
    public func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startMonitoring()
    }

    /// Reset TCC permission database entry for OpenClip if macOS TCC is caching a stale signature.
    public func resetTCCAndRelaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", "com.openclip.OpenClip"]
        do {
            try process.run()
        } catch {
            Log.permissions.error("Failed to launch tccutil reset for Accessibility permission: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        
        relaunchApp()
    }

    /// Relaunch the app so macOS TCC registers the new permission for the running process.
    public func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Internal

    /// Direct TCC query — bypasses any in-process caching.
    private static func queryAX() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }
}
