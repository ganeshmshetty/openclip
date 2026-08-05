// Constants.swift
// OpenClip
//
// Defines system-wide configuration constants, timing thresholds, key codes, and default settings keys.
import Foundation
import CoreGraphics

public enum Constants {
    public static let filterDelay: TimeInterval = 0.075
    public static let elementTimeout: TimeInterval = 0.3
    public static let maxTextLength: Int = 10_485_760
    public static let pasteboardRestoreDelay: TimeInterval = 0.8
    public static let cVirtualKey: CGKeyCode = 0x08
    public static let deleteVirtualKey: CGKeyCode = 0x33
    public static let vVirtualKey: CGKeyCode = 0x09
    public static let pasteboardWaitInterval: TimeInterval = 0.05
    public static let pasteboardWaitTimeout: TimeInterval = 0.5
    public static let pasteboardWaitSleep: UInt64 = 50_000_000
    public static let popupOffset: CGFloat = 16.0
    public static let popupPadding: CGFloat = 8.0
    public static let popupDismissalDistance: CGFloat = 280.0
    /// Action-search palette sizing: visible result rows and result row height.
    public static let searchMaxRows: Int = 5
    public static let searchResultRowHeight: CGFloat = 32
    /// Fraction of an extra result row shown beyond `searchMaxRows` so the next action peeks,
    /// hinting that the list scrolls.
    public static let searchPeekRowFraction: CGFloat = 0.5
    /// Height cap for the popup panel while in search mode (field row + 5 result rows + padding).
    public static let searchMaxHeight: CGFloat = 240
    /// Delay before the hover info bubble appears (400ms).
    public static let bubbleHoverDelayNanoseconds: UInt64 = 400_000_000
    /// Delay before the long-press result bubble fires (600ms).
    public static let bubbleLongPressNanoseconds: UInt64 = 600_000_000
    public static let isAppEnabledKey: String = "isAppEnabled"
    public static let maxURLScanLength: Int = 2000
    public static let actionErrorDomain: String = "OpenClip.ActionError"
    public static let actionErrorCode: Int = 1

    /// Query-value encoding charset that escapes `&`, `=`, `+`, `?`, `#`, etc.
    /// (stricter than `.urlQueryAllowed`, which leaves those characters unescaped
    /// and corrupts URLs built from user-selected text).
    ///
    /// `%` is also excluded: `.urlQueryAllowed` permits it, so an already-escaped
    /// sequence such as `%2F` in the selection would otherwise pass through as an
    /// escape sequence and be reinterpreted by the destination URL instead of being
    /// treated as the literal characters `%2F`.
    public static var queryValueAllowed: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "%:#[]@!$&'()*+,;=?")
        return allowed
    }
    
    public static let symbolPrefix: String = "symbol("
    public static let symbolSuffix: String = ")"
    public static let imageExtensions: [String] = [".png", ".jpg", ".jpeg", ".icns", ".gif", ".svg"]
    
    public static let rulesFileURL: URL = URL(fileURLWithPath: ("~/.openclip/rules.json" as NSString).expandingTildeInPath)
    
    // Extension System Constants
    public static let extensionsDirectory: URL = URL(fileURLWithPath: ("~/.openclip/extensions" as NSString).expandingTildeInPath)
    public static let manifestFileName: String = "openclip.json"
    public static let legacyManifestFileName: String = "manifest.json"
    public static let extKeyIdentifier: String = "Identifier"
    public static let extKeyName: String = "Name"
    public static let extKeyActions: String = "Actions"
    public static let extKeyTitle: String = "Title"
    public static let extKeyIcon: String = "Icon"
    public static let extKeyScript: String = "Script"
    
    public static let defaultScriptName: String = "script.sh"
    public static let defaultIconSymbol: String = "wand.and.stars"
    public static let customIdentifierPrefix: String = "com.custom."
    public static let titlePrefixHash: String = "# Title:"
    public static let titlePrefixSlash: String = "// Title:"
    public static let iconPrefixHash: String = "# Icon:"
    public static let iconPrefixSlash: String = "// Icon:"
    public static let identifierPrefixHash: String = "# Identifier:"
    public static let identifierPrefixSlash: String = "// Identifier:"
    
    public static let actionTypePaste: String = "paste"
    public static let actionTypeCopy: String = "copy"
    public static let actionTypeOpenURL: String = "openURL"
    
    public static let envVarText: String = "OPENCLIP_TEXT"
    public static let envVarMatched: String = "OPENCLIP_MATCHED"
    public static let envVarCapturePrefix: String = "OPENCLIP_CAPTURE_"
    public static let envVarBundleID: String = "OPENCLIP_BUNDLE_ID"
    public static let envVarActionID: String = "OPENCLIP_ACTION_ID"
    public static let shortcutsBinaryPath: String = "/usr/bin/shortcuts"
    public static let maxHeaderLinesToScan: Int = 50

    /// Maximum wall-clock runtime for shell/AppleScript/JS subprocess actions before they are killed,
    /// preventing a hanging script from leaving the popup spinning forever.
    public static let scriptTimeout: TimeInterval = 30

    /// Guards against zip-slip path traversal: true only when `destinationURL`
    /// resolves to a path equal to or strictly inside `baseDirectory`.
    ///
    /// Symlinks are resolved on both paths before comparing: `standardizingPath`
    /// only normalizes the path text, so a symlink inside `baseDirectory` that
    /// points outside it would otherwise defeat the lexical containment check.
    public static func isPathSafe(destinationURL: URL, baseDirectory: URL) -> Bool {
        let destPath = (destinationURL.resolvingSymlinksInPath().path as NSString).standardizingPath
        let basePath = (baseDirectory.resolvingSymlinksInPath().path as NSString).standardizingPath
        guard destPath.hasPrefix(basePath) else { return false }
        // Ensure the next character is a separator so /foo/bar doesn't accept /foo/bar2
        let remainder = destPath.dropFirst(basePath.count)
        if remainder.isEmpty { return true }
        return remainder.hasPrefix("/")
    }
    
    // Preferences Keys
    public static let disabledActionIDsKey: String = "disabledActionIDs"
    public static let startAtLoginKey: String = "startAtLogin"
}
