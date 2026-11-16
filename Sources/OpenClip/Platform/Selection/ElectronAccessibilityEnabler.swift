import AppKit
import ApplicationServices
import Core

/// Electron builds no web-content AX tree until an assistive client sets
/// `AXManualAccessibility` on its application element. Without that tree the selection in an
/// Electron app (Claude, Slack, VS Code, ChatGPT) is readable only through a synthetic Copy.
/// Chrome ignores this attribute, so detection is limited to Electron bundles — canonical or
/// renamed — and apps without the attribute simply ignore the set.
@MainActor
internal final class ElectronAccessibilityEnabler {
    typealias Setter = @Sendable (pid_t) -> AXError

    static let shared = ElectronAccessibilityEnabler()
    nonisolated static let attribute = "AXManualAccessibility"

    private let isElectron: @MainActor (NSRunningApplication) -> Bool
    private let setter: Setter
    /// Keyed by pid and launch date so a recycled pid is not mistaken for an earlier process.
    private var decided: Set<String> = []

    init(
        isElectron: @escaping @MainActor (NSRunningApplication) -> Bool = { ElectronAccessibilityEnabler.isElectronApp(bundleURL: $0.bundleURL) },
        setter: @escaping Setter = ElectronAccessibilityEnabler.setManualAccessibility
    ) {
        self.isElectron = isElectron
        self.setter = setter
    }

    /// Requests the AX tree once per process. The set runs off the main actor; a failure clears
    /// the decision so the next activation retries.
    func enableIfNeeded(for app: NSRunningApplication?) {
        guard let app, app.processIdentifier > 0,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let key = Self.key(for: app)
        guard decided.insert(key).inserted, isElectron(app) else { return }
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? "unknown"
        let setter = self.setter
        Task.detached(priority: .utility) { [weak self] in
            let error = setter(pid)
            Log.selection.debug("monitor: \(ElectronAccessibilityEnabler.attribute, privacy: .public) set for \(bundleID, privacy: .public) result=\(error.rawValue, privacy: .public)")
            guard error != .success else { return }
            await self?.forget(key)
        }
    }

    private func forget(_ key: String) {
        decided.remove(key)
    }

    private static func key(for app: NSRunningApplication) -> String {
        "\(app.processIdentifier)-\(app.launchDate?.timeIntervalSince1970 ?? 0)"
    }

    nonisolated static func isElectronApp(bundleURL: URL?) -> Bool {
        guard let bundleURL else { return false }
        let fileManager = FileManager.default
        let contents = bundleURL.appendingPathComponent("Contents")
        let framework = contents.appendingPathComponent("Frameworks/Electron Framework.framework")
        if fileManager.fileExists(atPath: framework.path) { return true }
        // Electron forks may rename the framework (the Codex app ships "Codex Framework.framework").
        // Every Electron build also keeps its app source under Resources, as an archive or a
        // directory; Chrome and native apps do not. Setting AXManualAccessibility on a false
        // positive is harmless — apps without the attribute ignore it.
        let resources = contents.appendingPathComponent("Resources")
        return fileManager.fileExists(atPath: resources.appendingPathComponent("app.asar").path)
            || fileManager.fileExists(atPath: resources.appendingPathComponent("app").path)
    }

    nonisolated static func setManualAccessibility(pid: pid_t) -> AXError {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, Float(Constants.axReadTimeout))
        return AXUIElementSetAttributeValue(element, attribute as CFString, kCFBooleanTrue)
    }
}
