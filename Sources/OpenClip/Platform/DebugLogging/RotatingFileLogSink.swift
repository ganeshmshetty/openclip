// RotatingFileLogSink.swift
// OpenClip
//
// Thread-safe rotating file appender for OpenClip logs.
// Writes formatted entries to ~/Library/Logs/OpenClip/openclip.log on a serial queue.
// Rotates when file size reaches maxFileSize (default 5MB), keeping up to maxBackups files.

import Foundation
import Core

public final class RotatingFileLogSink: LogSink, @unchecked Sendable {
    public static var defaultLogDirectory: URL {
        let libraryLogs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return libraryLogs.appendingPathComponent("Logs/OpenClip")
    }

    private let logDirectory: URL
    private let fileName: String
    private let maxFileSize: UInt64
    private let maxBackups: Int

    private let queue = DispatchQueue(label: "com.openclip.log.fileappender", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public init(
        logDirectory: URL? = nil,
        fileName: String = "openclip.log",
        maxFileSize: UInt64 = 5 * 1024 * 1024,
        maxBackups: Int = 3
    ) {
        self.logDirectory = logDirectory ?? Self.defaultLogDirectory
        self.fileName = fileName
        self.maxFileSize = maxFileSize
        self.maxBackups = maxBackups

        queue.sync {
            self.prepareLogFile()
        }
    }

    deinit {
        let handle = fileHandle
        fileHandle = nil
        try? handle?.close()
    }

    public func record(date: Date, category: String, level: LogLevel, message: String) {
        let formattedDate = dateFormatter.string(from: date)
        let line = "\(formattedDate) \(level.displayName) \(category) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        queue.async { [weak self] in
            self?.write(data)
        }
    }

    public func flush() {
        queue.sync {
            try? fileHandle?.synchronize()
        }
    }

    private var currentFileURL: URL {
        logDirectory.appendingPathComponent(fileName)
    }

    private func backupFileURL(index: Int) -> URL {
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let backupName = ext.isEmpty ? "\(baseName).\(index)" : "\(baseName).\(index).\(ext)"
        return logDirectory.appendingPathComponent(backupName)
    }

    private func prepareLogFile() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: logDirectory.path) {
            try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }

        let fileURL = currentFileURL
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            self.fileHandle = handle
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            self.currentFileSize = attributes[.size] as? UInt64 ?? 0
        } catch {
            self.fileHandle = nil
            self.currentFileSize = 0
        }
    }

    private func write(_ data: Data) {
        if currentFileSize + UInt64(data.count) > maxFileSize {
            rotate()
        }

        guard let fileHandle else {
            prepareLogFile()
            guard let fileHandle else { return }
            fileHandle.write(data)
            currentFileSize += UInt64(data.count)
            return
        }

        fileHandle.write(data)
        currentFileSize += UInt64(data.count)
    }

    private func rotate() {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil

        let fileManager = FileManager.default

        // Delete excess backup if exists
        let highestBackup = backupFileURL(index: maxBackups)
        if fileManager.fileExists(atPath: highestBackup.path) {
            try? fileManager.removeItem(at: highestBackup)
        }

        // Shift backups down: (maxBackups - 1) down to 1
        if maxBackups > 1 {
            for i in stride(from: maxBackups - 1, through: 1, by: -1) {
                let src = backupFileURL(index: i)
                let dst = backupFileURL(index: i + 1)
                if fileManager.fileExists(atPath: src.path) {
                    try? fileManager.moveItem(at: src, to: dst)
                }
            }
        }

        // Move current file to backup 1
        let current = currentFileURL
        if fileManager.fileExists(atPath: current.path) && maxBackups > 0 {
            let backup1 = backupFileURL(index: 1)
            try? fileManager.moveItem(at: current, to: backup1)
        }

        // Create fresh log file
        prepareLogFile()
    }
}
