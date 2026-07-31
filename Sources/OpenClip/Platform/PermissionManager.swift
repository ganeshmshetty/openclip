import AppKit
import ApplicationServices

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

    /// Open System Settings → Accessibility and start polling.
    public func requestAccessibilityPermission() {
        // Passing nil avoids the deprecated kAXTrustedCheckOptionPrompt global var
        // and lets us open System Settings ourselves with the correct deep link.
        _ = AXIsProcessTrustedWithOptions(nil)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startMonitoring()
    }

    /// Relaunch the app so macOS TCC registers the new permission for the running process.
    public func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        // NSWorkspace.OpenConfiguration has no `createsNewApplicationInstance` on all SDK versions;
        // use the Process-based relaunch approach instead.
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
