// AboutTabView.swift
// OpenClip
//
// The About preferences tab: app identity, version, software updates, links, and diagnostics.
// Styled with inset SettingsCards (outside headers, rounded cards, inset hairline dividers).

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
        ScrollView {
            VStack(spacing: 20) {
                // Identity block
                identityBlock

                // Software updates
                SettingsCard("Software Updates") {
                    if let newVersion = updateManager.availableUpdateVersion {
                        updateAvailableRow(version: newVersion)
                        SettingsDivider()

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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            SettingsDivider()
                        }
                    }

                    SettingsToggleRow(
                        title: "Automatically Download Updates",
                        isOn: $updateManager.automaticallyDownloadsUpdates
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Notify on Update",
                        isOn: $updateManager.notifyOnUpdate
                    )

                    SettingsDivider()

                    SettingsRow(
                        title: "Check for Updates",
                        subtitle: updateChannelSubtitle ?? lastCheckedSubtitle
                    ) {
                        HStack(spacing: 10) {
                            Picker("", selection: $updateManager.updateChannel) {
                                Text("Stable").tag(UpdateChannel.stable)
                                Text("Beta").tag(UpdateChannel.beta)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                            .accessibilityLabel("Update Channel")

                            Button {
                                updateManager.checkForUpdates()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(SettingsDesignTokens.primaryText)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .settingsGlassCircle()
                            .contentShape(Circle())
                            .disabled(!updateManager.canCheckForUpdates)
                            .accessibilityLabel("Check Now")
                            .help("Check Now")
                        }
                    }
                }

                // Links
                SettingsCard("Links") {
                    linkRow("Website", systemImage: "globe", url: "https://www.getopenclip.app")
                    SettingsDivider()
                    linkRow("Documentation", systemImage: "book", url: "https://www.getopenclip.app/docs")
                    SettingsDivider()
                    linkRow("Support", systemImage: "questionmark.circle", url: "https://www.getopenclip.app/support")
                    SettingsDivider()
                    linkRow("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: "https://github.com/ganeshmshetty/openclip")
                    SettingsDivider()
                    linkRow("Report an Issue", systemImage: "ant", url: "https://github.com/ganeshmshetty/openclip/issues")
                }

                // Diagnostics
                SettingsCard("Diagnostics") {
                    SettingsRow(
                        title: "Logs",
                        subtitle: "Attach these when reporting a problem."
                    ) {
                        HStack(spacing: 10) {
                            Button(isExporting ? String(localized: "Exporting…") : String(localized: "Export…")) {
                                exportLogs()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                            .disabled(isExporting)

                            Button(String(localized: "Reveal")) {
                                LogExporter.showLogsInFinder()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .settingsGlassCapsule()
                            .contentShape(Capsule())
                        }
                    }
                }

                Text("Open source under AGPL-3.0 License")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Pieces

    private var identityBlock: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 72, height: 72)

            Text("OpenClip")
                .font(.title2.weight(.semibold))
                .foregroundStyle(SettingsDesignTokens.primaryText)

            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Instant actions for selected text on macOS")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                openURL("https://www.getopenclip.app/support")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption.weight(.semibold))
                    Text(String(localized: "Donate"))
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func updateAvailableRow(version newVersion: String) -> some View {
        SettingsRow(
            title: updateManager.isUpdateStagedForQuitInstall
                ? "Update Ready"
                : "Update Available",
            subtitle: LocalizedStringKey("Version \(newVersion)")
        ) {
            HStack(spacing: 10) {
                if #available(macOS 26.0, *) {
                    Button(String(localized: "Update Now")) {
                        updateManager.installUpdateNow()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.glassButtonBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(.ultraThinMaterial, in: .capsule)
                    .glassEffect(.regular.tint(SettingsDesignTokens.glassButtonBlue.opacity(0.18)).interactive(), in: .capsule)
                    .contentShape(Capsule())

                    Button(String(localized: "On Quit")) {
                        updateManager.installUpdateOnQuit()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .settingsGlassCapsule()
                    .contentShape(Capsule())
                } else {
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
    }

    private var lastCheckedSubtitle: LocalizedStringKey? {
        guard let lastCheck = updateManager.lastUpdateCheckDate else { return nil }
        return LocalizedStringKey("Last checked \(Self.shortTimeAgo(lastCheck))")
    }

    private var updateChannelSubtitle: LocalizedStringKey? {
        updateManager.updateChannel == .beta
            ? "Beta builds include features that are still being tested."
            : nil
    }

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
                SettingsRouter.shared.notifyError(
                    title: String(localized: "Export Logs Failed"),
                    message: error.localizedDescription
                )
            }
        }
    }
}
