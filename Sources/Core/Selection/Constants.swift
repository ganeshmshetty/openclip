import Foundation
import CoreGraphics

public enum Constants {
    public static let filterDelay: TimeInterval = 0.075
    public static let elementTimeout: TimeInterval = 0.3
    public static let maxTextLength: Int = 10_485_760
    public static let maxProcessingLength: Int = 51_200
    public static let pasteboardRestoreDelay: TimeInterval = 0.8
    public static let cVirtualKey: CGKeyCode = 0x08
    public static let pasteboardWaitInterval: TimeInterval = 0.05
    public static let pasteboardWaitTimeout: TimeInterval = 0.5
    public static let pasteboardWaitSleep: UInt64 = 50_000_000
}
