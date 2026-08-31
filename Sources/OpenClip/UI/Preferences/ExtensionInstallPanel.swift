// ExtensionInstallPanel.swift
// OpenClip
//
// Shared "Install File…" NSOpenPanel presenter for the extension store and installed
// extensions views. Split out of ExtensionsStoreView.swift.
import AppKit
import Core

/// Presents an open panel for picking a `.openclipext` folder, `.zip`, or script file and
/// installs it via `ExtensionManager`, posting the extensions-did-change notification on success.
@MainActor
func presentInstallExtensionPanel() {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Select Extension to Install")
    panel.message = String(localized: "Choose a .openclipext folder, .zip archive, or script file")
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = true
    panel.allowedContentTypes = []

    panel.begin { response in
        guard response == .OK, let selectedURL = panel.url else { return }
        Task {
            do {
                _ = try await ExtensionManager.shared.installExtension(from: selectedURL, source: ExtensionSource.package.rawValue)
                await MainActor.run {
                    NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Extension Install Failed")
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: String(localized: "OK"))
                    alert.runModal()
                }
            }
        }
    }
}
