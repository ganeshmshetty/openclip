// DefaultAppRules.swift
// OpenClip
//
// Strongly-typed catalog of default application rules and macro groups.
import Foundation

public enum DefaultAppRules: Sendable {
    public static let menuCopyApps: [String] = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "dev.zed.Zed",
        "com.github.atom",
        "com.sublimetext.*",
        "notion.id",
        "md.obsidian",
        "com.figma.Desktop",
        "net.whatsapp.WhatsApp"
    ]
    
    public static let catalog: [AppRule] = [
        AppRule(
            bundleIdentifiers: [":menu-copy-apps:"],
            useMenuCopy: true
        ),
        AppRule(
            bundleIdentifiers: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"],
            denyPaste: true
        )
    ]
}
