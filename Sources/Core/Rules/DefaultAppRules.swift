// DefaultAppRules.swift
// OpenClip
//
// Strongly-typed catalog of default application rules and macro groups.
import Foundation

public enum DefaultAppRules: Sendable {
    public static let safariGroup: [String] = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS"
    ]
    
    public static let chromiumGroup: [String] = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.pushplaylabs.sidekick",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper",
        "com.operasoftware.OperaGX",
        "org.chromium.Thorium",
        "com.sigmaos.sigmaos.macos",
        "com.quark.desktop",
        "net.imput.helium",
        "ai.perplexity.comet",
        "com.openai.atlas",
        "org.ecosia.browser"
    ]
    
    public static let firefoxGroup: [String] = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "net.waterfox.waterfox",
        "org.mozilla.librewolf",
        "app.zen-browser.zen"
    ]
    
    public static let arcGroup: [String] = [
        "company.thebrowser.Browser",
        "company.thebrowser.dia"
    ]
    
    public static let keyboardCopyApps: [String] = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "dev.zed.Zed",
        "com.github.atom",
        "com.sublimetext.*",
        "notion.id",
        "md.obsidian",
        "com.figma.Desktop",
        "net.whatsapp.WhatsApp",
        "com.evernote.Evernote",
        "com.jetbrains.*",
        "com.1password.1password",
        "com.apple.iBooksX"
    ]
    
    public static let menuCopyApps: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty"
    ]
    
    /// The full pre-narrowing menu-copy list, kept for the `:menu-copy-apps:` macro so existing
    /// user rules files keep expanding to the same apps.
    public static let legacyMenuCopyApps: [String] = [
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
            bundleIdentifiers: safariGroup,
            retrievalMode: .browserScript
        ),
        AppRule(
            bundleIdentifiers: chromiumGroup,
            retrievalMode: .browserScript
        ),
        AppRule(
            bundleIdentifiers: firefoxGroup,
            retrievalMode: .browserScript
        ),
        AppRule(
            bundleIdentifiers: arcGroup,
            retrievalMode: .browserScript
        ),
        AppRule(
            bundleIdentifiers: keyboardCopyApps,
            retrievalMode: .keyboardCopy
        ),
        AppRule(
            bundleIdentifiers: menuCopyApps,
            retrievalMode: .menuCopy
        ),
        AppRule(
            bundleIdentifiers: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"],
            denyPaste: true
        )
    ]
}
