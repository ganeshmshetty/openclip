// LogExporter.swift
// OpenClip
//
// Collects and exports OpenClip log files as a compressed zip archive,
// and provides convenience actions for locating logs in Finder.

import AppKit
import Foundation
import Core

public enum LogExporterError: LocalizedError, Equatable {
    case noLogFilesFound
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noLogFilesFound:
            return "No log files found to export."
        case .exportFailed(let reason):
            return "Failed to export logs: \(reason)"
        }
    }
}

@MainActor
public enum LogExporter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Flushes the rotating log sink, archives all matching `openclip*.log` files
    /// into a timestamped zip in the temporary directory, and returns the archive URL.
    @discardableResult
    public static func exportLogs(
        from directory: URL = RotatingFileLogSink.defaultLogDirectory,
        date: Date = Date()
    ) async throws -> URL {
        RotatingFileLogSink.shared?.flush()

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            throw LogExporterError.noLogFilesFound
        }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let logFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("openclip") && name.hasSuffix(".log")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !logFiles.isEmpty else {
            throw LogExporterError.noLogFilesFound
        }

        let dateString = dateFormatter.string(from: date)
        let archiveName = "OpenClip-Logs-\(dateString).zip"
        let archiveURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(archiveName)

        if fileManager.fileExists(atPath: archiveURL.path) {
            try? fileManager.removeItem(at: archiveURL)
        }

        let filePaths = logFiles.map(\.path)
        let arguments = ["-q", "-j", archiveURL.path] + filePaths

        let invocation = ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: arguments
        )

        _ = try await ShellProcessRunner.run(invocation)

        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw LogExporterError.exportFailed("Zip archive was not created.")
        }

        return archiveURL
    }

    /// Opens Finder and selects/reveals the logs directory.
    public static func showLogsInFinder(directory: URL = RotatingFileLogSink.defaultLogDirectory) {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
    }
}
