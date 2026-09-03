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
    @State private var exportError: String?
    @ObservedObject private var updateManager = AppUpdateManager.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            // ── App Identity ──
            VStack(spacing: 6) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.bottom, 2)

                Text("OpenClip")
                    .font(.system(size: 20, weight: .bold))

                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Instant actions for selected text on macOS")
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                    .padding(.top, 2)
            }

            // ── Updates Card ──
            VStack(alignment: .leading, spacing: 6) {
                if let newVersion = updateManager.availableUpdateVersion {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                                .foregroundStyle(.tint)
                            Text(updateManager.isUpdateStagedForQuitInstall
                                 ? String(localized: "Update Ready: v\(newVersion)")
                                 : String(localized: "Update Available: v\(newVersion)"))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button {
                                updateManager.installUpdateNow()
                            } label: {
                                Text(String(localized: "Update Now"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button {
                                updateManager.installUpdateOnQuit()
                            } label: {
                                Text(String(localized: "Update on Quit"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if let notes = updateManager.availableUpdateReleaseNotes, !notes.isEmpty {
                            DisclosureGroup(String(localized: "Release Notes")) {
                                ScrollView {
                                    Text(notes)
                                        .font(.system(size: 11))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .padding(6)
                                }
                                .frame(maxHeight: 100)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Row 1: Automatically Download Updates
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                        .foregroundColor(updateManager.automaticallyDownloadsUpdates ? .accentColor : .secondary)
                        .frame(width: 18, alignment: .center)

                    Text(String(localized: "Automatically Download Updates"))
                        .font(.system(size: 12))

                    Spacer()

                    Toggle("", isOn: $updateManager.automaticallyDownloadsUpdates)
                        .labelsHidden()
                        .controlSize(.mini)
                        .accessibilityLabel(String(localized: "Automatically Download Updates"))
                }
                .padding(.vertical, 2)

                // Row 2: Notify on Update
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 13))
                        .foregroundColor(updateManager.notifyOnUpdate ? .accentColor : .secondary)
                        .frame(width: 18, alignment: .center)

                    Text(String(localized: "Notify on Update"))
                        .font(.system(size: 12))

                    Spacer()

                    Toggle("", isOn: $updateManager.notifyOnUpdate)
                        .labelsHidden()
                        .controlSize(.mini)
                        .accessibilityLabel(String(localized: "Notify on Update"))
                }
                .padding(.vertical, 2)

                Divider()
                    .padding(.vertical, 2)

                // Row 3: Check for Updates Status & Button
                HStack(spacing: 8) {
                    if let lastCheck = updateManager.lastUpdateCheckDate {
                        Text(String(localized: "Last checked: \(Self.shortTimeAgo(lastCheck))"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        updateManager.checkForUpdates()
                    } label: {
                        Text(String(localized: "Check for Updates"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!updateManager.canCheckForUpdates)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.top, 20)

            // ── Links & Diagnostics ──
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    actionButton("Website", icon: "globe") {
                        openURL("https://www.getopenclip.app")
                    }
                    actionButton("GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                        openURL("https://github.com/ganeshmshetty/openclip")
                    }
                    actionButton("Issues", icon: "ant") {
                        openURL("https://github.com/ganeshmshetty/openclip/issues")
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        exportLogs()
                    } label: {
                        HStack(spacing: 5) {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 11))
                            }
                            Text(isExporting ? String(localized: "Exporting…") : String(localized: "Export Logs"))
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isExporting)

                    Button {
                        LogExporter.showLogsInFinder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Reveal Log File")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.top, 14)

            // ── Footer ──
            Text("Open source under MIT License")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .alert("Export Logs Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {
                exportError = nil
            }
        } message: {
            Text(exportError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Helpers

    private func actionButton(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

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
                exportError = error.localizedDescription
            }
        }
    }
}
