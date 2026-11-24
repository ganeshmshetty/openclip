// LocalExtensionInstaller.swift
// OpenClip
//
// Prompts user confirmation and installs local extension packages (.openclipext)
// opened via Finder double-click or drag-and-drop.
import AppKit
import Core
import Foundation

@MainActor
public final class LocalExtensionInstaller: Sendable {
    public static let shared = LocalExtensionInstaller()

    private var openPreferences: () -> Void = {}

    /// Prompt handler used to present alerts. Defaults to running `NSAlert.runModal()`,
    /// but can be overridden in tests to simulate user interaction without blocking.
    public var promptHandler: (NSAlert) -> NSApplication.ModalResponse = { alert in
        alert.runModal()
    }

    private init() {}

    public func configure(openPreferences: @escaping () -> Void) {
        self.openPreferences = openPreferences
    }

    /// Determines if a file URL points to an OpenClip extension package (.openclipext or .openclipext.zip).
    public static func isExtensionPackageURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "openclipext" { return true }
        if ext == "zip" && url.deletingPathExtension().pathExtension.lowercased() == "openclipext" {
            return true
        }
        return false
    }

    /// Prompts for user consent, then installs the package at `fileURL` into `~/.openclip/extensions`.
    public func install(from fileURL: URL) async {
        guard fileURL.isFileURL else {
            Log.extensions.error("Cannot install non-file URL: \(fileURL.absoluteString, privacy: .public)")
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            Log.extensions.error("Extension file does not exist at \(fileURL.path, privacy: .public)")
            let notFoundAlert = NSAlert()
            notFoundAlert.messageText = String(localized: "Extension Not Found")
            notFoundAlert.informativeText = String(localized: "The extension package could not be found at the specified location.")
            notFoundAlert.alertStyle = .warning
            _ = promptHandler(notFoundAlert)
            return
        }

        // Try reading manifest info before prompting if it is a directory bundle
        let manifest: ExtensionMetadata? = {
            if isDirectory.boolValue {
                if let manifestURL = ExtensionManifestStore.manifestFileURL(in: fileURL) {
                    return ExtensionManifestStore.readManifest(at: manifestURL)
                }
            }
            return nil
        }()

        let displayName = manifest?.name.isEmpty == false
            ? manifest!.name
            : fileURL.deletingPathExtension().lastPathComponent
        let initialPackageID = manifest?.identifier ?? fileURL.deletingPathExtension().lastPathComponent

        NSApp.activate()

        let confirmAlert = NSAlert()
        confirmAlert.messageText = String(localized: "Install Extension?")

        var details: [String] = []
        if let version = manifest?.version, !version.isEmpty {
            details.append(String(localized: "Version: \(version)"))
        }
        if let author = manifest?.author, !author.isEmpty {
            details.append(String(localized: "Author: \(author)"))
        }
        if let description = manifest?.description, !description.isEmpty {
            details.append(description)
        }

        let detailSection = details.isEmpty ? "" : details.joined(separator: "\n") + "\n\n"
        confirmAlert.informativeText = String(
            localized: "Do you want to install \"\(displayName)\"?\n\n\(detailSection)Extensions can run scripts and actions when you select text. Only proceed if you trust this source."
        )
        confirmAlert.alertStyle = .informational
        confirmAlert.addButton(withTitle: String(localized: "Install"))
        confirmAlert.addButton(withTitle: String(localized: "Cancel"))

        guard promptHandler(confirmAlert) == .alertFirstButtonReturn else {
            Log.extensions.info("User cancelled installation of local extension: \(initialPackageID, privacy: .public)")
            return
        }

        do {
            ExtensionManager.shared.prepareInstall(source: "package", packageID: initialPackageID)
            let installedActions = try await ExtensionManager.shared.installExtension(from: fileURL, source: "package")

            let resolvedPackageID = installedActions.compactMap { ActionIdentity.extensionPackageID(of: $0) }.first ?? initialPackageID
            await ExtensionManager.shared.enablePackage(packageID: resolvedPackageID)

            Log.extensions.notice("Successfully installed local extension '\(resolvedPackageID, privacy: .public)'. Total actions: \(installedActions.count)")

            let successAlert = NSAlert()
            successAlert.messageText = String(localized: "Extension Installed")
            successAlert.informativeText = String(localized: "\"\(displayName)\" was installed successfully and is ready to use.")
            successAlert.alertStyle = .informational
            successAlert.addButton(withTitle: String(localized: "OK"))
            successAlert.addButton(withTitle: String(localized: "View in Settings"))

            if promptHandler(successAlert) == .alertSecondButtonReturn {
                openPreferences()
            }
        } catch {
            Log.extensions.error("Failed to install local extension '\(initialPackageID, privacy: .public)': \(error.localizedDescription, privacy: .private)")
            let failureAlert = NSAlert()
            failureAlert.messageText = String(localized: "Extension Install Failed")
            failureAlert.informativeText = String(localized: "OpenClip could not install \"\(displayName)\": \(error.localizedDescription)")
            failureAlert.alertStyle = .warning
            _ = promptHandler(failureAlert)
        }
    }
}
