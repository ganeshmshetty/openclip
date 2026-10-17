// PermissionManager.swift
// OpenClip
//
// Checks and prompts for required macOS Accessibility permissions necessary for text retrieval and event monitoring.
import AppKit
import ApplicationServices
import Core

/// Polls `AXIsProcessTrusted` with an async loop on the main actor rather than a Timer.
@MainActor
public final class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()

    @Published public private(set) var isAccessibilityGranted: Bool = false
    /// Screen Recording, needed only by Capture Text. Optional: the rest of the app works without it.
    @Published public private(set) var isScreenRecordingGranted: Bool = false

    private var pollingTask: Task<Void, Never>?

    private init() {
        self.isAccessibilityGranted = Self.queryAX()
        self.isScreenRecordingGranted = Self.queryScreenRecording()
    }

    // MARK: - Public API

    public func startMonitoring() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.checkStatus()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            }
        }
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func checkStatus() {
        let current = Self.queryAX()
        if isAccessibilityGranted != current {
            isAccessibilityGranted = current
            NotificationCenter.default.post(name: .openClipAccessibilityChanged, object: current)
        }
        let screenRecording = Self.queryScreenRecording()
        if isScreenRecordingGranted != screenRecording {
            isScreenRecordingGranted = screenRecording
        }
    }

    /// Asks TCC to list OpenClip under Screen Recording, then opens the pane. macOS usually applies a
    /// new grant only after the app restarts, so the row keeps showing "Required" until relaunch.
    /// A rebuilt or updated copy with a new signature leaves a stale TCC entry that macOS lists as
    /// off or hides entirely, so an ungranted request clears that entry first and re-registers.
    public func requestScreenRecordingPermission() {
        startMonitoring()
        Task { @MainActor in
            if !Self.queryScreenRecording() {
                await Self.resetScreenRecordingEntry()
                _ = CGRequestScreenCaptureAccess()
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func resetScreenRecordingEntry() async {
        do {
            _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
                arguments: ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.openclip.OpenClip"],
                environment: [:]
            ))
        } catch {
            Log.permissions.error("Failed to reset Screen Recording permission: \(error.localizedDescription)")
        }
    }

    /// Prompts TCC to evaluate the running binary. TCC entries are reset only by `resetTCCAndRelaunch`.
    public func requestAccessibilityPermission() {
        startMonitoring()
        promptAndOpenAccessibilitySettings()
    }

    private func promptAndOpenAccessibilitySettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reset TCC permission database entry for OpenClip if macOS TCC is caching a stale signature.
    public func resetTCCAndRelaunch() {
        // Async: never `waitUntilExit` on the main actor. The app relaunches regardless.
        Task {
            do {
                _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                    executableURL: URL(fileURLWithPath: "/usr/bin/tccutil"),
                    arguments: ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.openclip.OpenClip"],
                    environment: [:]
                ))
            } catch {
                Log.permissions.error("Failed to run tccutil reset for Accessibility permission: \(error.localizedDescription)")
            }
            relaunchApp()
        }
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

    private static func queryScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
