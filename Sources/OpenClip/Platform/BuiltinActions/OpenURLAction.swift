import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct OpenURLAction: Action {
    public let id = "builtin.openurl"
    public let title = "Open Link"
    public let icon = ActionIcon.symbol("link")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasURLPrefix = text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("www.")
        return hasURLPrefix && extractURL(from: text) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        if let url = extractURL(from: context.selection.text) {
            return .openURL(url)
        }
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
    }
    
    private func extractURL(from text: String) -> URL? {
        let textToScan = String(text.prefix(Constants.maxURLScanLength))
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: textToScan, options: [], range: NSRange(location: 0, length: textToScan.utf16.count))
        return matches?.first?.url
    }
}
