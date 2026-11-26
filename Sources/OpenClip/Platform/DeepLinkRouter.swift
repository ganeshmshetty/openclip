// DeepLinkRouter.swift
// OpenClip
//
// The one place that acts on an inbound `openclip://` URL, dispatching to app commands or the extension
// installer. The grammar lives in Core (`OpenClipDeepLink`); `AppDelegate` delegates to `handle(_:)`.
//
// A URL scheme is unauthenticated, so there is no settings read/write route and no reply callback:
// deep links may only trigger effects, never expose or mutate configuration.
import AppKit
import Core
import Foundation

@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Shows the Settings window; injected by `AppDelegate`, which owns the status bar controller.
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
        guard RemoteExtensionInstaller.isAllowedSource(downloadURL) else {
            Log.extensions.error("Refused deep-link install from a source outside the allowlist")
            return
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? id
        let alert = NSAlert()
        alert.messageText = String(localized: "Install Extension?")
        alert.informativeText = String(localized: "OpenClip wants to install the extension \"\(displayName)\" from \(downloadURL.absoluteString). Extensions can run scripts when you select text. Only proceed if you trust this source.")
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
                Log.extensions.error("Failed to install extension '\(id, privacy: .public)' from \(downloadURL, privacy: .public): \(error.localizedDescription, privacy: .private)")
                let failure = NSAlert()
                failure.messageText = String(localized: "Extension Install Failed")
                failure.informativeText = String(localized: "OpenClip could not install \"\(id)\": \(error.localizedDescription)")
                failure.alertStyle = .warning
                failure.runModal()
            }
        }
    }
}
