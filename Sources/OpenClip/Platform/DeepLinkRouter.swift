// DeepLinkRouter.swift
// OpenClip
//
// The one place that acts on an inbound `openclip://` URL. It dispatches to the app-level commands
// or the extension installer.
//
// The grammar itself lives in Core (`OpenClipDeepLink`), so the app target only decides *how* to
// act. `AppDelegate.application(_:open:)` is a one-line delegate to `handle(_:)`.
//
// There is no settings read/write route and no reply callback: a URL scheme is unauthenticated, so
// it may only trigger effects, never expose or mutate configuration. See `OpenClipDeepLink`.
import AppKit
import Core
import Foundation

@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Brings OpenClip's Settings window forward. Injected by `AppDelegate`, which owns the status
    /// bar controller that shows it.
    private var openPreferences: () -> Void = {}

    private init() {}

    func configure(openPreferences: @escaping () -> Void) {
        self.openPreferences = openPreferences
    }

    /// Parses and performs `url`. Unknown or malformed URLs are logged and ignored.
    func handle(_ url: URL) {
        guard let link = OpenClipDeepLink.parse(url) else {
            Log.settings.notice("Ignoring unrecognised deep link")
            return
        }

        switch link {
        case .install(let id, let name, let downloadURL):
            install(id: id, name: name, downloadURL: downloadURL)

        case .command(let command):
            run(command)
        }
    }

    private func run(_ command: IntegrationCommand) {
        switch command {
        case .openSettings:
            openPreferences()
        case .pause:
            IntegrationSettings.pause()
        case .resume:
            IntegrationSettings.resume()
        }
    }

    // MARK: - Extension install (existing store deep link)

    private func install(id: String, name: String?, downloadURL: URL) {
        guard let host = downloadURL.host?.lowercased(),
              RemoteExtensionInstaller.allowedDownloadHosts.contains(host) else {
            Log.extensions.error("Refused deep-link install from a host outside the allowlist")
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Install Extension?")
        alert.informativeText = String(localized: "OpenClip wants to install the extension \"\(id)\" from \(host). Extensions can run scripts when you select text. Only proceed if you trust this source.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Install"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            do {
                ExtensionManager.shared.prepareInstall(source: "store", packageID: id)
                _ = try await RemoteExtensionInstaller.shared.installFromRemoteURL(downloadURL, extensionID: id)
                await ExtensionUpdateManager.shared.checkForUpdates()
            } catch {
                Log.extensions.error("Failed to install extension '\(id, privacy: .public)' from host \(host, privacy: .public): \(error.localizedDescription, privacy: .private)")
                let failure = NSAlert()
                failure.messageText = String(localized: "Extension Install Failed")
                failure.informativeText = String(localized: "OpenClip could not install \"\(id)\": \(error.localizedDescription)")
                failure.alertStyle = .warning
                failure.runModal()
            }
        }
    }
}
