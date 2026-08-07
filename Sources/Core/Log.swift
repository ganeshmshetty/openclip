// Log.swift
// OpenClip
//
// Single logging surface for the OpenClip Core + App targets.
//
// Every subsystem owns a fixed, greppable `os.Logger` category, so logs can be filtered by
// subsystem in Console.app / `log stream`. See `docs/logging.md` for the category table and the
// per-subsystem filtering workflow.
//
// Conventions:
//   - Levels: `.notice` for lifecycle transitions, `.error` for recoverable failures that still
//     surface to the user, `.fault` only for subprocess crashes / invariant violations.
//   - Messages are structured and greppable: include the action id, extension id, and error domain.
//   - Anything touching selected text, clipboard content, or extension-authored data stays
//     default-private; ids and URLs are the only values marked `privacy: .public`.
//   - Never log in hot paths (per-mouse-move hover updates, high-frequency view bodies).

import Foundation
import os

/// Central logging surface. Add a category here (not a brand-new `Logger` instance) whenever a new
/// subsystem starts emitting logs, and keep the table in `docs/logging.md` in step.
public enum Log {
    /// Bundle / process identifier shared by every logged message.
    public static let subsystem = "com.openclip"

    // MARK: Core subsystems (settings, rules, policies)
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let presentation = Logger(subsystem: subsystem, category: "presentation")
    public static let chrome = Logger(subsystem: subsystem, category: "chrome")
    public static let factory = Logger(subsystem: subsystem, category: "factory")
    public static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
    public static let resultHandler = Logger(subsystem: subsystem, category: "result-handler")

    // MARK: Runtime owners
    public static let shell = Logger(subsystem: subsystem, category: "shell")
    public static let js = Logger(subsystem: subsystem, category: "js")
    public static let selection = Logger(subsystem: subsystem, category: "selection")
    public static let extensions = Logger(subsystem: subsystem, category: "extensions")
    public static let ai = Logger(subsystem: subsystem, category: "ai")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let icons = Logger(subsystem: subsystem, category: "icons")
}