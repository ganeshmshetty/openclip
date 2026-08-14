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
        "com.google.Chrome.*",
        "org.chromium.*",
        "com.brave.Browser.*",
        "com.microsoft.edgemac.*",
        "com.pushplaylabs.sidekick",
        "com.vivaldi.Vivaldi.*",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper",
        "com.operasoftware.OperaGX",
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
        "company.thebrowser.*"
    ]
    
    public static let nativeApps: [String] = [
        "com.apple.Notes",
        "com.apple.TextEdit",
        "com.apple.mail",
        "com.apple.finder",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote",
        "com.apple.MobileSMS",
        "com.apple.reminders",
        "com.apple.Preview",
        "com.apple.calculator",
        "com.apple.systempreferences",
        "com.apple.SystemSettings"
    ]
    
    public static let keyboardCopyApps: [String] = [
        // Code Editors & IDEs
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.visualstudio.code.oss",
        "com.todesktop.230313mzl4w4u92",
        "com.cursor.*",
        "com.exafunction.windsurf",
        "com.codeium.windsurf",
        "cn.trae.app",
        "com.byteplus.trae",
        "dev.zed.*",
        "com.sublimetext.*",
        "com.sublimemerge",
        "com.github.atom",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.macromates.TextMate",
        "com.coteditor.CotEditor",
        "org.vim.MacVim",
        "neovide",
        "com.jetbrains.*",
        "com.google.android.studio",
        "com.rstudio.positron",
        
        // Notes, Knowledge & Markdown
        "notion.id",
        "md.obsidian",
        "net.shinyfrog.bear",
        "com.lukilabs.lukiapp",
        "com.craft.Craft",
        "com.logseq.app",
        "io.anytype.anytype",
        "io.capacities.app",
        "com.upnote.app",
        "com.upnote",
        "abnerworks.Typora",
        "net.cozic.joplin-desktop",
        "com.supernotes.app",
        "app.supernotes",
        "com.roamresearch.desktop",
        "com.evernote.Evernote",
        "com.apple.iBooksX",
        "com.apple.iBooks",
        
        // Communication & Collaboration
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.hnc.DiscordCanary",
        "com.hnc.DiscordPTB",
        "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram",
        "org.whispersystems.signal-desktop",
        "net.whatsapp.WhatsApp",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "us.zoom.xos",
        "com.mattermost.Mattermost",
        "Mattermost.Desktop",
        "im.riot.app",
        
        // Design & Productivity
        "com.figma.Desktop",
        "com.linear",
        "com.linear.Linear",
        "com.postmanlabs.mac",
        "com.insomnia.app",
        "com.1password.1password",
        "com.spotify.client"
    ]
    
    public static let menuCopyApps: [String] = [
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.*",
        "com.github.wez.wezterm",
        "org.tabby",
        "com.raphaelamorim.rio",
        "com.waveterm.terminal",
        "org.contour-terminal.contour",
        "com.github.swordfeng.cool-retro-term",
        "cool-retro-term",
        "org.qtermy",
        "com.termius.*",
        "com.crystallogic.termius",
        "io.coressh.shell",
        "com.panic.Prompt",
        "com.panic.Prompt3",
        "com.lemonmojo.RoyalTSX.*",
        "com.vandyke.SecureCRT",
        "com.emtec.*",
        "com.decentsockets.Serial",
        "org.xquartz.*",
        "org.macosforge.xquartz.X11",
        "com.carnationsoftware.macwise",
        "com.subsquid.extraterm",
        "extraterm"
    ]
    
    public static let denyPasteApps: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.*",
        "com.github.wez.wezterm",
        "org.tabby",
        "com.raphaelamorim.rio",
        "com.waveterm.terminal",
        "org.contour-terminal.contour",
        "com.github.swordfeng.cool-retro-term",
        "cool-retro-term",
        "org.qtermy",
        "com.termius.*",
        "com.crystallogic.termius",
        "io.coressh.shell",
        "com.panic.Prompt",
        "com.panic.Prompt3",
        "com.lemonmojo.RoyalTSX.*",
        "com.vandyke.SecureCRT",
        "com.emtec.*",
        "com.decentsockets.Serial",
        "org.xquartz.*",
        "org.macosforge.xquartz.X11",
        "com.carnationsoftware.macwise",
        "com.subsquid.extraterm",
        "extraterm"
    ]
    
    public static let catalog: [AppRule] = [
        AppRule(
            bundleIdentifiers: nativeApps,
            retrievalMode: .axTextControl
        ),
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
            bundleIdentifiers: denyPasteApps,
            denyPaste: true
        )
    ]
}
