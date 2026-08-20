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
    panel.title = "Select Extension to Install"
    panel.message = "Choose a .openclipext folder, .zip archive, or script file"
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.treatsFilePackagesAsDirectories = true
    panel.allowedContentTypes = []

    panel.begin { response in
        guard response == .OK, let selectedURL = panel.url else { return }
        Task {
            do {
                let installed = try await ExtensionManager.shared.installExtension(from: selectedURL, source: ExtensionSource.package.rawValue)
                await MainActor.run {
                    NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    if let packageID = installed.first.flatMap({ ActionIdentity.extensionPackageID(of: $0) }) ?? installed.first?.id {
                        NotificationCenter.default.post(name: .openClipOpenTrustModel, object: nil, userInfo: ["packageID": packageID])
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Extension Install Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}
