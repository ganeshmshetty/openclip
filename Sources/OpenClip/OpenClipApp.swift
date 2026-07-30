import SwiftUI
import AppKit

/// The main entry point for the OpenClip application.
@main
struct OpenClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We do not want a main window for an agent app.
        // In SwiftUI, Settings{} creates a settings window if needed.
        Settings {
            EmptyView()
        }
    }
}
