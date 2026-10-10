// Constants.swift
// OpenClip
//
// Defines system-wide configuration constants, timing thresholds, key codes, and default settings keys.
import Foundation
import CoreGraphics

public enum Constants {
    public static let maxTextLength: Int = 10_485_760
    public static let pasteboardRestoreDelay: TimeInterval = 0.8
    public static let deleteVirtualKey: CGKeyCode = 0x33
    public static let vVirtualKey: CGKeyCode = 0x09
    public static let copyVirtualKey: CGKeyCode = 0x08
    public static let actionErrorDomain: String = "OpenClip.ActionError"
    public static let actionErrorCode: Int = 1

    /// Stricter than `.urlQueryAllowed`, which leaves `&`, `=`, `#`, `%` etc. unescaped and corrupts selection-built URLs.
    public static var queryValueAllowed: CharacterSet {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "%:#[]@!$&'()*+,;=?")
        return allowed
    }
    
    public static let symbolPrefix: String = "symbol("
    public static let symbolSuffix: String = ")"
    public static let imageExtensions: [String] = [".png", ".jpg", ".jpeg", ".icns", ".gif", ".svg"]
    
    public static let rulesFileURL: URL = URL(fileURLWithPath: ("~/.openclip/rules.json" as NSString).expandingTildeInPath)
    public static let secretsFileURL: URL = URL(fileURLWithPath: ("~/.openclip/secrets.json" as NSString).expandingTildeInPath)
    
    // Extension System Constants
    public static let extensionsDirectory: URL = URL(fileURLWithPath: ("~/.openclip/extensions" as NSString).expandingTildeInPath)
    public static let customIconsDirectory: URL = URL(fileURLWithPath: ("~/.openclip/custom_icons" as NSString).expandingTildeInPath)
    public static let customIconPrefix: String = "custom:"
    public static let manifestFileName: String = "openclip.json"
    public static let legacyManifestFileName: String = "manifest.json"
    public static let storePageLimit: Int = 12
    /// Page size for fetching the whole catalogue; `loadAll` keeps paging until the server is done.
    public static let storeFullCatalogLimit: Int = 500
    public static let extKeyIdentifier: String = "Identifier"
    public static let extKeyName: String = "Name"
    public static let extKeyActions: String = "Actions"
    public static let extKeyTitle: String = "Title"
    public static let extKeyIcon: String = "Icon"
    public static let extKeyScript: String = "Script"
    
    public static let defaultScriptName: String = "script.sh"
    public static let defaultIconSymbol: String = "plus"
    public static let defaultAIIconSymbol: String = "sparkle"
    public static let customIdentifierPrefix: String = "com.custom."
    public static let titlePrefixHash: String = "# Title:"
    public static let titlePrefixSlash: String = "// Title:"
    public static let iconPrefixHash: String = "# Icon:"
    public static let iconPrefixSlash: String = "// Icon:"
    public static let identifierPrefixHash: String = "# Identifier:"
    public static let identifierPrefixSlash: String = "// Identifier:"
    
    public static let actionTypePaste: String = "paste"
    public static let actionTypeCopy: String = "copy"
    public static let actionTypePasteContent: String = "pasteContent"
    public static let actionTypeCopyContent: String = "copyContent"
    public static let actionTypeOpenURL: String = "openURL"
    public static let actionTypeFile: String = "file"
    public static let actionTypeCopyFile: String = "copyFile"
    public static let actionTypeSaveFile: String = "saveFile"
    public static let outputsDirectory: URL = URL(fileURLWithPath: ("~/.openclip/cache/outputs" as NSString).expandingTildeInPath)
    
    public static let envVarText: String = "OPENCLIP_TEXT"
    public static let envVarHTML: String = "OPENCLIP_HTML"
    public static let envVarRTF: String = "OPENCLIP_RTF"
    public static let envVarMatched: String = "OPENCLIP_MATCHED"
    public static let envVarCapturePrefix: String = "OPENCLIP_CAPTURE_"
    public static let envVarBundleID: String = "OPENCLIP_BUNDLE_ID"
    public static let envVarActionID: String = "OPENCLIP_ACTION_ID"
    public static let envVarLocale: String = "OPENCLIP_LOCALE"
    public static let envVarLanguage: String = "OPENCLIP_LANGUAGE"
    public static let shortcutsBinaryPath: String = "/usr/bin/shortcuts"
    public static let maxHeaderLinesToScan: Int = 50

    /// Filename prefix for temporary .ics files handed to Calendar; shared by producer and cleaner.
    public static let icsFilenamePrefix: String = "OpenClipEvent-"

    /// Delay before a handed-off .ics file is deleted, long enough for Calendar to finish importing it.
    public static let icsCleanupDelay: TimeInterval = 20

    /// Max seconds for one AX inspect or Edit ▸ Copy press; a blocked AX call must not hold a permit past this.
    public static let axReadTimeout: TimeInterval = 0.5
    /// Max concurrent AX inspects and Edit ▸ Copy presses. Permits release at the deadline, not when a blocked call returns.
    public static let axMaxConcurrentInspects: Int = 4

    /// Hard deadline for the Paste-probe's AX menu walk so an unresponsive app cannot hang delivery; timeout reads as "unknown" (copy).
    public static let pasteProbeTimeout: TimeInterval = 0.4
    /// Max concurrent paste probes, separate from the inspect limit. Permits release at `pasteProbeTimeout`.
    public static let pasteProbeMaxConcurrent: Int = 4

    /// Hard deadline (seconds) for the browser-script retrieval bridge to return a selection.
    public static let browserScriptTimeout: TimeInterval = 1.0

    /// Hard deadline (seconds) for reading the clipboard after issuing a Cmd+C copy.
    public static let pasteboardCopyTimeout: TimeInterval = 0.25

    /// Longer copy-poll deadline for Safari, whose copy path settles more slowly.
    public static let safariPasteboardCopyTimeout: TimeInterval = 0.4

    /// Poll interval (seconds) while waiting for the AX web-area text to settle after focus.
    public static let webAreaSettleInterval: TimeInterval = 0.05

    /// Max polls before giving up on the AX web-area text settling.
    public static let webAreaSettleMaxRetries: Int = 6

    /// Throttle interval (seconds) for keyboard selection gestures (Cmd+A, Shift+arrow) to prevent rapid repeated retrievals while holding keys.
    public static let keyboardSelectionDebounceInterval: TimeInterval = 0.15

    /// Maximum age (seconds) for a monitored selection before it is treated as stale.
    public static let selectionMaxAge: TimeInterval = 30.0

    /// Default duration (seconds) of holding the mouse button down to trigger the popup.
    public static let defaultMouseHoldDuration: TimeInterval = 0.3

    /// Cap on in-flight synchronous JS evaluations: a CPU-bound script cannot be interrupted in JavaScriptCore, so each one parks a pool thread.
    public static let maxConcurrentSyncScriptEvaluations: Int = 4

    /// Zip-slip guard. Symlinks are resolved first because `standardizingPath` only normalizes text.
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
}
