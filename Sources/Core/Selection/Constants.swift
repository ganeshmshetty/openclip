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
    public static let popupDismissalDistance: CGFloat = 40.0
    public static let searchURLTemplate: String = "https://www.google.com/search?q=%@"
    public static let maxURLScanLength: Int = 2000
    public static let actionErrorDomain: String = "OpenClip.ActionError"
    public static let actionErrorCode: Int = 1
    
    // Extension System Constants
    public static let extensionsDirectory: URL = URL(fileURLWithPath: ("~/.openclip/extensions" as NSString).expandingTildeInPath)
    public static let manifestFileName: String = "manifest.json"
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
    
    public static let envVarText: String = "POPCLIP_TEXT"
    public static let maxHeaderLinesToScan: Int = 50
}
