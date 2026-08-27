import Foundation
import AppKit
import Core

@MainActor
public final class AXHelperHost: Sendable {
    public static let shared = AXHelperHost()

    public init() {}

    public func helperBundleURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("\(AXHelperConstants.helperExecutableName).app")
    }

    public func startHelperIfNeeded() {
        let bundleURL = helperBundleURL()
        let executableURL = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(AXHelperConstants.helperExecutableName)

        guard FileManager.default.fileExists(atPath: executableURL.path) else {
            Log.permissions.notice("AX Helper executable not found at \(executableURL.path, privacy: .public); using fallback")
            return
        }

        // Check if already running
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AXHelperConstants.helperBundleIdentifier)
        if !running.isEmpty {
            Log.permissions.notice("AX Helper is already running")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { app, error in
            if let error {
                Log.permissions.error("Failed to launch AX Helper: \(error.localizedDescription)")
            } else {
                Log.permissions.notice("Successfully launched AX Helper process")
            }
        }
    }

    public func stopHelper() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AXHelperConstants.helperBundleIdentifier)
        for app in running {
            app.terminate()
        }
    }
}
