import Foundation

public struct AppFilter: Sendable {
    public static let excludedBundleIDPatterns: [String] = [
        "com.adobe.*",
        "com.adobe.aerendercore",
        "com.amazon.Kindle",
        "com.apple.CharacterPaletteIM",
        "com.apple.dock",
        "com.apple.iphonesimulator",
        "com.apple.systemuiserver",
        "com.blizzard.*",
        "com.codeweavers.*",
        "com.collectorz.*",
        "com.oracle.SQLDeveloper",
        "com.parallels.*",
        "com.pilotmoon.popclip",
        "com.pixelmatorteam.*",
        "com.revolversoftware.office",
        "com.screencastomatic.app",
        "com.unity3d.*",
        "com.vmware.*",
        "net.java.openjdk.cmd",
        "org.keepassx.keepassx",
        "org.vim.MacVim",
        "com.edovia.screens.*",
        "com.jetbrains.*"
    ]
    
    public static func isExcluded(bundleID: String) -> Bool {
        for pattern in excludedBundleIDPatterns {
            if pattern.hasSuffix(".*") {
                let prefix = String(pattern.dropLast(2))
                if bundleID.hasPrefix(prefix) { return true }
            } else {
                if bundleID == pattern { return true }
            }
        }
        return false
    }
}
