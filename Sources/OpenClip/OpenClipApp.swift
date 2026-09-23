// OpenClipApp.swift
// OpenClip
//
// Defines the AppKit application entrypoint for OpenClip.
import AppKit

/// The main entry point for the OpenClip application.
@main
@MainActor
final class OpenClipApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

