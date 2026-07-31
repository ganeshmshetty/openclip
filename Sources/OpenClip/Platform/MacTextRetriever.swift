import AppKit
import ApplicationServices
import Foundation
import Core
import os

internal final class MacTextRetriever: TextRetrieving, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.openclip", category: "MacTextRetriever")
    
    internal init() {}
    internal func retrieveText(for app: any AppIdentifying, policy: AppPolicyContext) async -> String? {
        if policy.grabPasteboard {
            if let text = await extractViaPasteboard() { return text }
            return nil
        }
        
        if let text = await extractViaAccessibility() { return text }
        if let text = await extractViaPasteboard() { return text }
        if let nsApp = app as? NSRunningApplication, let text = await extractViaAppleScript(for: nsApp) { return text }
        return nil
    }
    
    private func extractViaAccessibility() async -> String? {
        let timeout = Constants.elementTimeout
        let logger = self.logger
        
        actor RaceManager {
            private var isCompleted = false
            func complete(with result: String?, continuation: CheckedContinuation<String?, Never>) {
                if !isCompleted {
                    isCompleted = true
                    continuation.resume(returning: result)
                }
            }
        }
        
        let manager = RaceManager()
        
        return await withCheckedContinuation { continuation in
            let fetchTask = Task.detached { () -> String? in
                let systemWide = AXUIElementCreateSystemWide()
                var focusedElement: CFTypeRef?
                let focusedError = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                
                guard focusedError == .success, let element = focusedElement else {
                    if focusedError != .success {
                        logger.error("AXUIElementCopyAttributeValue focusedElement error: \(focusedError.rawValue)")
                    }
                    await manager.complete(with: nil, continuation: continuation)
                    return nil
                }
                
                guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
                    await manager.complete(with: nil, continuation: continuation)
                    return nil
                }
                let axElement = element as! AXUIElement
                var selectedText: CFTypeRef?
                let textError = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedText)
                
                guard textError == .success, let text = selectedText as? String else {
                    if textError != .success {
                        logger.error("AXUIElementCopyAttributeValue selectedText error: \(textError.rawValue)")
                    }
                    await manager.complete(with: nil, continuation: continuation)
                    return nil
                }
                
                let result = text.isEmpty ? nil : text
                await manager.complete(with: result, continuation: continuation)
                return result
            }
            
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                fetchTask.cancel()
                await manager.complete(with: nil, continuation: continuation)
            }
        }
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
        let cmddown = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: true)
        cmddown?.flags = .maskCommand
        let cmdup = CGEvent(keyboardEventSource: src, virtualKey: Constants.cVirtualKey, keyDown: false)
        cmdup?.flags = .maskCommand
        cmddown?.post(tap: .cghidEventTap)
        cmdup?.post(tap: .cghidEventTap)
        
        var waitTime = 0.0
        while pasteboard.changeCount == initialChangeCount && waitTime < Constants.pasteboardWaitTimeout {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: Constants.pasteboardWaitSleep)
            waitTime += Constants.pasteboardWaitInterval
        }
        
        if pasteboard.changeCount == initialChangeCount { return nil }
        let text = pasteboard.string(forType: .string)
        
        let changeCountAfterCopy = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.pasteboardRestoreDelay * 1_000_000_000))
            if NSPasteboard.general.changeCount == changeCountAfterCopy {
                if let savedItems = savedItems {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects(savedItems)
                }
            }
        }
        return text
    }
    
    private func extractViaAppleScript(for app: NSRunningApplication) async -> String? {
        guard let localizedName = app.localizedName else { return nil }
        let bundleName = localizedName.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "\(bundleName)"
            try
                return the selection as text
            on error
                return ""
            end try
        end tell
        """
        
        let task = Task.detached {
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
        return await task.value
    }
}
