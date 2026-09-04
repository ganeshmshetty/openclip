// OpenURLAction.swift
// OpenClip
//
// Implements URL opening actions using macOS NSWorkspace workspace services.
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct OpenURLAction: Action {
    public let id = "builtin.openurl"
    public var title: String { String(localized: "Open Link") }
    public let icon = ActionIcon.symbol("link")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return extractURL(from: context.selection.text) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        if let url = extractURL(from: context.selection.text) {
            return .openURL(url)
        }
        return .failure(NSError(
            domain: Constants.actionErrorDomain,
            code: Constants.actionErrorCode,
            userInfo: [NSLocalizedDescriptionKey: String(localized: "No valid URL found in selection.")]
        ))
    }
    
    private static let allowedWebSchemes: Set<String> = ["http", "https"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    private static let specialURLRegex: NSRegularExpression? = {
        let pattern = "(?i)(?<=^|[\\s<(\"'\\[“‘])(?:localhost(?::\\d+)(?:/[^\\s>\")\\]]*)?|localhost/[^\\s>\")\\]]+|(?:127\\.0\\.0\\.1|192\\.168\\.\\d{1,3}\\.\\d{1,3}|10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|(?:\\d{1,3}\\.){3}\\d{1,3}:\\d+)(?::\\d+)?(?:/[^\\s>\")\\]]*)?)"
        return try? NSRegularExpression(pattern: pattern)
    }()
    
    public func extractURL(from text: String) -> URL? {
        Self.extractFirstURL(from: text)
    }
    
    public static func extractFirstURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if trimmed.lowercased() == "localhost" {
            return URL(string: "http://localhost")
        }
        
        let textToScan = String(text.prefix(Constants.maxURLScanLength))
        let range = NSRange(location: 0, length: textToScan.utf16.count)
        var candidates: [(range: NSRange, url: URL)] = []
        
        // 1. Scan for standard web URLs and bare domains via NSDataDetector
        if let matches = linkDetector?.matches(in: textToScan, options: [], range: range) {
            for match in matches {
                if let rawURL = match.url,
                   let swiftRange = Range(match.range, in: textToScan) {
                    let matchedText = String(textToScan[swiftRange])
                    let cleanedString = cleanURLString(rawURL.absoluteString)
                    guard let cleanedURL = URL(string: cleanedString) else { continue }
                    
                    var finalURL = cleanedURL
                    // If NSDataDetector synthesized http:// for a www. or bare domain that lacked an explicit scheme, upgrade to https
                    if !matchedText.lowercased().hasPrefix("http://") && cleanedURL.scheme?.lowercased() == "http" {
                        var components = URLComponents(url: cleanedURL, resolvingAgainstBaseURL: false)
                        components?.scheme = "https"
                        if let upgradedURL = components?.url {
                            finalURL = upgradedURL
                        }
                    }
                    
                    // Reject non-web schemes (e.g. mailto:, ftp:, tel:, magnet:, etc.)
                    guard let scheme = finalURL.scheme?.lowercased(), allowedWebSchemes.contains(scheme) else {
                        continue
                    }
                    candidates.append((match.range, finalURL))
                }
            }
        }
        
        // 2. Scan for localhost and raw IP endpoints via regex
        if let regexMatches = specialURLRegex?.matches(in: textToScan, range: range) {
            for match in regexMatches {
                if let swiftRange = Range(match.range, in: textToScan) {
                    let matchedRaw = String(textToScan[swiftRange])
                    let cleaned = cleanURLString(matchedRaw)
                    guard !cleaned.isEmpty else { continue }
                    
                    let urlString = "http://" + cleaned
                    if let url = URL(string: urlString),
                       let scheme = url.scheme?.lowercased(),
                       allowedWebSchemes.contains(scheme) {
                        candidates.append((match.range, url))
                    }
                }
            }
        }
        
        // Pick the URL that appears earliest in the scanned text, preferring the longer match on ties
        candidates.sort {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }
        return candidates.first?.url
    }
    
    private static func cleanURLString(_ urlString: String) -> String {
        var s = urlString
        while let last = s.last {
            if last == ")" {
                let openCount = s.filter { $0 == "(" }.count
                let closeCount = s.filter { $0 == ")" }.count
                if closeCount > openCount {
                    s.removeLast()
                    continue
                }
            } else if last == "]" {
                let openCount = s.filter { $0 == "[" }.count
                let closeCount = s.filter { $0 == "]" }.count
                if closeCount > openCount {
                    s.removeLast()
                    continue
                }
            }
            let trailingChars = CharacterSet(charactersIn: ".,;:!?>\"'”’")
            if let scalar = last.unicodeScalars.first, trailingChars.contains(scalar) {
                s.removeLast()
                continue
            }
            break
        }
        return s
    }
}
