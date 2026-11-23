// BrowserDocumentURL.swift
// OpenClip
//
// Reads the page URL of the frontmost browser window through Accessibility. The focused window's
// AXDocument attribute is what Safari and the Chromium browsers expose for the active tab, so no
// Apple Events permission is needed on top of the Accessibility grant OpenClip already uses.
import AppKit
import ApplicationServices
import Core

@MainActor
enum BrowserDocumentURL {
    /// One gesture can read the URL twice (hold, then mouse-up). A short cache keeps that to one AX
    /// round trip without leaving a stale page in place after a tab switch.
    private static let cacheLifetime: TimeInterval = 1
    private static var cache: [pid_t: (url: URL?, at: Date)] = [:]

    static func focusedDocumentURL(for app: NSRunningApplication, now: Date = Date()) -> URL? {
        if let entry = cache[app.processIdentifier], now.timeIntervalSince(entry.at) < cacheLifetime {
            return entry.url
        }
        let url = read(app)
        cache[app.processIdentifier] = (url, now)
        return url
    }

    static func clearCache() {
        cache.removeAll()
    }

    private static func read(_ app: NSRunningApplication) -> URL? {
        guard BrowserDetector.isBrowser(bundleIdentifier: app.bundleIdentifier),
              AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, Float(Constants.axReadTimeout))
        guard let rawWindow = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = rawWindow as! AXUIElement
        AXUIElementSetMessagingTimeout(window, Float(Constants.axReadTimeout))
        guard let document = attribute(window, kAXDocumentAttribute) as? String,
              let url = URL(string: document), url.scheme != nil else { return nil }
        return url
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
