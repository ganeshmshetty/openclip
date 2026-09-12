// AboutTabView.swift
// OpenClip
//
// The About preferences tab: app identity, version, software updates, links, and diagnostics.
// Split out of PreferencesView.swift.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Core

@MainActor
struct AboutTab: View {
    @State private var isExporting = false
    @ObservedObject private var updateManager = AppUpdateManager.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        Form {
            Section {
                if let newVersion = updateManager.availableUpdateVersion {
                    updateAvailableRow(version: newVersion)

                    if let notes = updateManager.availableUpdateReleaseNotes, !notes.isEmpty {
                        DisclosureGroup("Release Notes") {
                            ScrollView {
                                Text(LocalizedStringKey(notes))
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                            }
                            .frame(maxHeight: 140)
                        }
                    }
                }

                SettingsToggleRow(
                    title: "Automatically Download Updates",
                    systemImage: "arrow.down.circle",
                    isOn: $updateManager.automaticallyDownloadsUpdates
                )

                SettingsToggleRow(
                    title: "Notify on Update",
                    systemImage: "bell.badge",
                    isOn: $updateManager.notifyOnUpdate
                )

                SettingsRow(
                    title: "Check for Updates",
                    subtitle: lastCheckedSubtitle,
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    Button("Check Now") {
                        updateManager.checkForUpdates()
                    }
                    .disabled(!updateManager.canCheckForUpdates)
                }
            } header: {
                // The identity block rides the first section's header: a header
                // scrolls with the form and draws no card, where a pinned top
                // inset let the rows slide underneath it.
                VStack(spacing: 0) {
                    identityBlock
                    Text("Software Updates")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Links") {
                linkRow("Website", systemImage: "globe", url: "https://www.getopenclip.app")
                linkRow(
                    "GitHub",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/ganeshmshetty/openclip"
                )
                linkRow(
                    "Report an Issue",
                    systemImage: "ant",
                    url: "https://github.com/ganeshmshetty/openclip/issues"
                )
            }

            Section("Diagnostics") {
                SettingsRow(
                    title: "Logs",
                    subtitle: "Attach these when reporting a problem.",
                    systemImage: "doc.text"
                ) {
                    HStack(spacing: 10) {
                        Button(isExporting ? "Exporting…" : "Export…") {
                            exportLogs()
                        }
                        .disabled(isExporting)

                        Button("Reveal") {
                            LogExporter.showLogsInFinder()
                        }
                    }
                }
            }

            Section {
                Text("Open source under MIT License")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Pieces

    private var identityBlock: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 72, height: 72)

            Text("OpenClip")
                .font(.title2.weight(.semibold))

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Instant actions for selected text on macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func updateAvailableRow(version newVersion: String) -> some View {
        SettingsRow(
            title: updateManager.isUpdateStagedForQuitInstall
                ? "Update Ready"
                : "Update Available",
            subtitle: LocalizedStringKey("Version \(newVersion)"),
            systemImage: "sparkles"
        ) {
            HStack(spacing: 10) {
                Button("Update Now") {
                    updateManager.installUpdateNow()
                }
                .buttonStyle(.borderedProminent)

                Button("On Quit") {
                    updateManager.installUpdateOnQuit()
                }
            }
        }
    }

    private var lastCheckedSubtitle: LocalizedStringKey? {
        guard let lastCheck = updateManager.lastUpdateCheckDate else { return nil }
        return LocalizedStringKey("Last checked \(Self.shortTimeAgo(lastCheck))")
    }

    /// Secondary navigation, so the whole row is the target and the only
    /// decoration is the outward arrow — a bordered button per link read as
    /// three competing primary actions.
    private func linkRow(_ title: LocalizedStringKey, systemImage: String, url: String) -> some View {
        Button {
            openURL(url)
        } label: {
            SettingsRow(title: title, systemImage: systemImage) {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Returns a short, static "time ago" string that doesn't live-tick.
    private static func shortTimeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return String(localized: "just now") }
        let minutes = seconds / 60
        if minutes < 60 { return String(localized: "\(minutes)m ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours)h ago") }
        let days = hours / 24
        if days == 1 { return String(localized: "yesterday") }
        if days < 7 { return String(localized: "\(days)d ago") }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func exportLogs() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let tempZipURL = try await LogExporter.exportLogs()
                defer {
                    try? FileManager.default.removeItem(at: tempZipURL)
                }

                let panel = NSSavePanel()
                panel.title = String(localized: "Export Logs")
                panel.nameFieldStringValue = tempZipURL.lastPathComponent
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = true

                if panel.runModal() == .OK, let destinationURL = panel.url {
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: tempZipURL, to: destinationURL)
                }
            } catch {
                // Inline, where the window shows every failure, rather than a modal alert.
                SettingsRouter.shared.notifyError(
                    title: String(localized: "Export Logs Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }
}
