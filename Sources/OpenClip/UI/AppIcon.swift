// AppIcon.swift
// OpenClip
//
// Loads the app icon directly from the bundle's AppIcon.icns so UI surfaces always
// render the custom icon. NSApp.applicationIconImage can fall back to the generic
// placeholder for agent (LSUIElement) apps; reading the resource avoids that path.
import AppKit

enum AppIcon {
    static var image: NSImage {
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            return icon
        }
        return NSApp.applicationIconImage
    }
}
