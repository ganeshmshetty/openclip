// WebsitePattern.swift
// Core
//
// Matches a page URL against a user-entered website pattern. Patterns are intentionally globs,
// not regular expressions: they come from the settings UI and only need to describe a site.
import Foundation

public enum WebsitePattern {
    /// Case-insensitive match of `url` against `pattern`.
    ///
    /// A pattern without a slash matches the host and its subdomains. A pattern with a slash
    /// matches the host and path, where `*` matches any run of characters. Schemes, a leading
    /// `www.`, query strings, and fragments are ignored on both sides.
    public static func matches(_ url: URL, pattern: String) -> Bool {
        guard let rawHost = url.host, !rawHost.isEmpty else { return false }
        let host = stripWWW(rawHost.lowercased())
        guard let needle = normalize(pattern) else { return false }

        if !needle.contains("/") {
            return host == needle || host.hasSuffix("." + needle)
        }

        let hostPath = host + url.path.lowercased()
        if needle.contains("*") {
            return glob(hostPath, needle)
        }
        return hostPath == needle || hostPath.hasPrefix(needle + "/")
    }

    /// A pattern that blocks the page's host and first path segment, such as `google.com/maps`.
    /// The path matcher already treats that as a prefix, so no wildcard is needed.
    public static func suggestion(for url: URL) -> String? {
        guard let rawHost = url.host, !rawHost.isEmpty else { return nil }
        let host = stripWWW(rawHost.lowercased())
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = segments.first else { return host }
        return host + "/" + first.lowercased()
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let cut = value.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            value = String(value[..<cut])
        }
        value = stripWWW(value)
        if value.hasPrefix("*.") {
            value = String(value.dropFirst(2))
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? nil : value
    }

    private static func glob(_ value: String, _ pattern: String) -> Bool {
        var expression = "^"
        for character in pattern {
            if character == "*" {
                expression += ".*"
            } else {
                expression += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        expression += "$"
        return value.range(of: expression, options: .regularExpression) != nil
    }
}
