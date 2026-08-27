import Foundation

@objc(AXHelperServiceProtocol)
public protocol AXHelperServiceProtocol {
    func ping(withReply reply: @escaping @Sendable (Bool) -> Void)
    func checkAccessibilityPermission(prompt: Bool, withReply reply: @escaping @Sendable (Bool) -> Void)
    func retrieveSelectedText(pid: Int32, withReply reply: @escaping @Sendable (Data?) -> Void)
    func postKey(keyCode: UInt16, flags: UInt64, withReply reply: @escaping @Sendable (Bool) -> Void)
}

public enum AXHelperConstants {
    public static let machServiceName = "com.openclip.OpenClip.helper"
    public static let helperBundleIdentifier = "com.openclip.OpenClip.helper"
    public static let helperExecutableName = "OpenClipAXHelper"
}
