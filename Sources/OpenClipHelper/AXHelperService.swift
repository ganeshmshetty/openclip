import Foundation
import AppKit
import ApplicationServices
import Core

@objc
public final class AXHelperService: NSObject, AXHelperServiceProtocol, NSXPCListenerDelegate, Sendable {
    public static let shared = AXHelperService()

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AXHelperServiceProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    public func ping(withReply reply: @escaping @Sendable (Bool) -> Void) {
        reply(true)
    }

    public func checkAccessibilityPermission(prompt: Bool, withReply reply: @escaping @Sendable (Bool) -> Void) {
        let options = prompt ? ["AXTrustedCheckOptionPrompt": true] as CFDictionary : nil
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        reply(isTrusted)
    }

    public func retrieveSelectedText(pid: Int32, withReply reply: @escaping @Sendable (Data?) -> Void) {
        let appElement = AXUIElementCreateApplication(pid_t(pid))
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            reply(nil)
            return
        }
        let focusedElement = focusedElementRef as! AXUIElement

        var textRef: CFTypeRef?
        var selectedText: String? = nil
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &textRef) == .success,
           let text = textRef as? String, !text.isEmpty {
            selectedText = text
        }

        var boundsX: Double? = nil
        var boundsY: Double? = nil
        var boundsW: Double? = nil
        var boundsH: Double? = nil

        var selectedRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
           let rangeValue = selectedRangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(focusedElement, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef) == .success,
               let boundsVal = boundsRef as! AXValue? {
                var rect = CGRect.zero
                if AXValueGetValue(boundsVal, .cgRect, &rect) {
                    boundsX = rect.origin.x
                    boundsY = rect.origin.y
                    boundsW = rect.size.width
                    boundsH = rect.size.height
                }
            }
        }

        let payload = AXSelectionPayload(
            text: selectedText,
            boundsX: boundsX,
            boundsY: boundsY,
            boundsWidth: boundsW,
            boundsHeight: boundsH,
            sourceBundleID: NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        )

        let data = try? JSONEncoder().encode(payload)
        reply(data)
    }

    public func postKey(keyCode: UInt16, flags: UInt64, withReply reply: @escaping @Sendable (Bool) -> Void) {
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let keydown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let keyup = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            reply(false)
            return
        }
        keydown.flags = CGEventFlags(rawValue: flags)
        keyup.flags = CGEventFlags(rawValue: flags)
        keydown.post(tap: .cghidEventTap)
        keyup.post(tap: .cghidEventTap)
        reply(true)
    }
}
