import Foundation

/// Shared native text recognition. Performs no file existence checks or UI effects.
public enum NativeContentDetector {
    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    private static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

    public static func detect(_ text: String, type: ContentType) -> DetectedContent {
        var result = DetectedContent()
        switch type {
        case .url, .email:
            let matches = linkMatches(in: text)
            result.urls = webURLs(in: text, matches: matches).map(\.absoluteString)
            result.emails = matches.compactMap { match in
                guard match.url?.scheme?.lowercased() == "mailto",
                      let range = Range(match.range, in: text) else { return nil }
                let raw = String(text[range])
                return raw.lowercased().hasPrefix("mailto:") ? String(raw.dropFirst(7)) : raw
            }
        case .date:
            result.dates = nativeMatches(dateDetector, in: text).compactMap { match in
                guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
                return DetectedContent.DateItem(text: String(text[range]), date: date,
                                                duration: match.duration, timeZone: match.timeZone?.identifier)
            }
        case .phone:
            result.phones = nativeMatches(phoneDetector, in: text).compactMap(\.phoneNumber)
        case .address:
            result.addresses = nativeMatches(addressDetector, in: text).compactMap { match in
                guard let components = match.addressComponents, let range = Range(match.range, in: text) else { return nil }
                let names: [(NSTextCheckingKey, String)] = [
                    (.name, "name"), (.jobTitle, "jobTitle"), (.organization, "organization"),
                    (.street, "street"), (.city, "city"), (.state, "state"), (.zip, "postalCode"),
                    (.country, "country"), (.phone, "phone")
                ]
                var fields: [String: String] = [:]
                for (key, name) in names { fields[name] = components[key] }
                return DetectedContent.AddressItem(text: String(text[range]), components: fields)
            }
        case .path:
            result.paths = paths(in: text)
        }
        return result
    }

    private static func nativeMatches(_ detector: NSDataDetector?, in text: String) -> [NSTextCheckingResult] {
        detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }

    private static func linkMatches(in text: String) -> [NSTextCheckingResult] {
        nativeMatches(linkDetector, in: text)
    }

    private static let allowedWebSchemes: Set<String> = ["http", "https"]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    
    private static let specialURLRegex: NSRegularExpression? = {
        let pattern = "(?i)(?<=^|[\\s<(\"'\\[“‘])(?:localhost(?::\\d+)(?:/[^\\s>\")\\]]*)?|localhost/[^\\s>\")\\]]+|(?:127\\.0\\.0\\.1|192\\.168\\.\\d{1,3}\\.\\d{1,3}|10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|(?:\\d{1,3}\\.){3}\\d{1,3}:\\d+)(?::\\d+)?(?:/[^\\s>\")\\]]*)?)"
        return try? NSRegularExpression(pattern: pattern)
    }()
    
    public static func urls(in text: String) -> [URL] {
        webURLs(in: text, matches: linkMatches(in: text))
    }

    private static func webURLs(in text: String, matches: [NSTextCheckingResult]) -> [URL] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        if trimmed.lowercased() == "localhost" {
            return [URL(string: "http://localhost")!]
        }
        
        let textToScan = text
        let range = NSRange(location: 0, length: textToScan.utf16.count)
        var candidates: [(range: NSRange, url: URL)] = []
        
        // 1. Scan for standard web URLs and bare domains via NSDataDetector
        do {
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
        // The native detector and special endpoint regex can report overlapping matches.
        // Keep the longest match at a position; retain separate repeated occurrences.
        var accepted: [(range: NSRange, url: URL)] = []
        for candidate in candidates {
            if let last = accepted.last, NSIntersectionRange(last.range, candidate.range).length > 0 {
                continue
            }
            accepted.append(candidate)
        }
        return accepted.map(\.url)
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

    private static let pathPattern = try! NSRegularExpression(
        pattern: #"["“'‘]((?:file://|~/|/)[^"”'’\n]+)["”'’]|(?<![\w:/])(?:file://|~/|/)(?:\\ |[^\s"'“”‘’<>()\[\]])+"#
    )

    public static func paths(in text: String) -> [String] {
        pathPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let range = match.range(at: 1).location == NSNotFound ? match.range : match.range(at: 1)
            guard let swiftRange = Range(range, in: text) else { return nil }
            return normalizedPath(String(text[swiftRange]))
        }
    }

    public static func normalizedPath(_ raw: String) -> String? {
        var path = stripDelimiters(raw)
        if path.hasPrefix("file://") {
            guard let url = URL(string: path), url.isFileURL else { return nil }
            path = url.path
        }
        path = path.replacingOccurrences(of: "\\ ", with: " ")
        path = stripLineNumbersAndPunctuation(path)
        guard path.hasPrefix("/") || path.hasPrefix("~/") || path == "~" else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    private static func stripDelimiters(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(String, String)] = [
            ("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"),
            ("<", ">"), ("(", ")"), ("[", "]")
        ]
        for (lead, trail) in wrappers {
            if s.hasPrefix(lead) && s.hasSuffix(trail) && s.count >= (lead.count + trail.count) {
                s = String(s.dropFirst(lead.count).dropLast(trail.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let leadingWrappers = CharacterSet(charactersIn: "\"‘“'<([")
        while let first = s.unicodeScalars.first, leadingWrappers.contains(first) {
            s.removeFirst()
        }
        let trailingWrappers = CharacterSet(charactersIn: "\"'”’)>]")
        while let last = s.unicodeScalars.last, trailingWrappers.contains(last) {
            s.removeLast()
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func stripLineNumbersAndPunctuation(_ raw: String) -> String {
        var s = raw
        // 1. Strip trailing sentence punctuation
        let trailingChars = CharacterSet(charactersIn: ".,;:!?\"'”’)]>")
        while let last = s.unicodeScalars.last, trailingChars.contains(last) {
            s.removeLast()
        }
        
        // 2. Strip compiler location suffix: :line:col or :line (e.g. :80:15 or :80)
        if let lastColon = s.lastIndex(of: ":") {
            let suffix = String(s[lastColon...])
            if suffix.count > 1 && suffix.dropFirst().allSatisfy({ $0.isNumber }) {
                s = String(s[..<lastColon])
                if let secondColon = s.lastIndex(of: ":") {
                    let secondSuffix = String(s[secondColon...])
                    if secondSuffix.count > 1 && secondSuffix.dropFirst().allSatisfy({ $0.isNumber }) {
                        s = String(s[..<secondColon])
                    }
                }
            }
        }
        return s
    }
}
