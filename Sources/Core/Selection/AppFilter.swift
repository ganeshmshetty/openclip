// AppFilter.swift
// OpenClip
//
// Identities that must never be targeted: OpenClip itself, system chrome, input methods, and
// clipboard managers with their own popup. App categories (VMs, remotes, emulators, editors) are
// default-disabled rules instead, so a user can re-enable them.
import Foundation

public struct AppFilter: Sendable {
    public static let excludedBundleIDPatterns: [String] = [
        "com.apple.CharacterPaletteIM",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.openclip.*",      // Never trigger on ourselves
        "com.pilotmoon.popclip",
        "net.java.openjdk.cmd"
    ]
    
    public static func isExcluded(bundleID: String) -> Bool {
        for pattern in excludedBundleIDPatterns {
            if pattern.hasSuffix(".*") {
                let prefix = String(pattern.dropLast(2))
                // Exact match OR subdomain match — prevents "com.foo" matching "com.foobar"
                if bundleID == prefix || bundleID.hasPrefix(prefix + ".") { return true }
            } else {
                if bundleID == pattern { return true }
            }
        }
        return false
    }
}
