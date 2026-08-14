// AboutTabView.swift
// OpenClip
//
// The About preferences tab: app icon, name, version, and diagnostics.
// Split out of PreferencesView.swift.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Core

@MainActor
struct AboutTab: View {
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 80, height: 80)
            
            VStack(spacing: 4) {
                Text("OpenClip")
                    .font(.title).bold()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("The open-source text selection action tool for macOS.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("Diagnostics")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 12) {
                    Button {
                        exportLogs()
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                            }
                            Text("Export Logs…")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExporting)

                    Button {
                        LogExporter.showLogsInFinder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                            Text("Show in Finder")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
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
                panel.title = "Export Logs"
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
