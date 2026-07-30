import AppKit
import ApplicationServices
import Foundation

public protocol TextRetrieving: Sendable {
    func retrieveText(for app: NSRunningApplication) async -> String?
}

public final class TextRetriever: TextRetrieving, Sendable {
    public init() {}
    public func retrieveText(for app: NSRunningApplication) async -> String? {
        if let text = await extractViaAccessibility() { return text }
        if let text = await extractViaPasteboard() { return text }
        if let text = await extractViaAppleScript(for: app) { return text }
        return nil
    }
    
    private func extractViaAccessibility() async -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusedError == .success, let element = focusedElement else { return nil }
        var selectedText: CFTypeRef?
        let textError = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textError == .success, let text = selectedText as? String else { return nil }
        return text.isEmpty ? nil : text
    }
    
    private func extractViaPasteboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        
        let initialChangeCount = pasteboard.changeCount
        let src = CGEventSource(stateID: .hidSystemState)
        let cmddown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cmddown?.flags = .maskCommand
        let cmdup = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cmdup?.flags = .maskCommand
        cmddown?.post(tap: .cghidEventTap)
        cmdup?.post(tap: .cghidEventTap)
        
        var waitTime = 0.0
        while pasteboard.changeCount == initialChangeCount && waitTime < 0.5 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waitTime += 0.05
        }
        
        if pasteboard.changeCount == initialChangeCount { return nil }
        let text = pasteboard.string(forType: .string)
        
        let delay: TimeInterval = 0.8
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if let savedItems = savedItems {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(savedItems)
            }
        }
        return text
    }
    
    private func extractViaAppleScript(for app: NSRunningApplication) async -> String? {
        guard let bundleName = app.localizedName else { return nil }
        let scriptSource = """
        tell application "\(bundleName)"
            try
                return the selection as text
            on error
                return ""
            end try
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let output = script.executeAndReturnError(&error)
            if error == nil {
                let text = output.stringValue
                return text?.isEmpty == false ? text : nil
            }
        }
        return nil
    }
}
