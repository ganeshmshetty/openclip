// SemanticVersion.swift
// OpenClip
//
// Minimal semantic-version value type used for `minOpenClipVersion` compatibility checks and
// extension update comparisons. Tolerant parse: leading "v" and any trailing prerelease/build
// text are accepted, but the triplet itself must be exactly three ASCII integer components
// (short or overflowing components are rejected outright).
// Pure Core — no AppKit/SwiftUI.
import Foundation

public struct SemanticVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Convenience failable initializer delegating to `parse`.
    public init?(string: String) {
        guard let version = SemanticVersion.parse(string) else { return nil }
        self = version
    }

    /// Parses a version string. Requires a full 3-component triplet where every component is a
    /// parseable ASCII integer (integer overflow and any short or empty component are rejected);
    /// returns nil otherwise. Leading "v" and trailing prerelease/build text are still tolerated.
    public static func parse(_ string: String) -> SemanticVersion? {
        var value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value = String(value.dropFirst())
        }
        // Cut at the first non-[0-9.] so "1.2.3-beta.1" becomes "1.2.3".
        if let stop = value.firstIndex(where: { !$0.isNumber && $0 != "." }) {
            value = String(value[..<stop])
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        func component(_ index: Int) -> Int? {
            let part = parts[index]
            // ASCII digits only, then a parse that also rejects overflow (Int(_:) returns nil).
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            return n
        }
        guard let major = component(0), let minor = component(1), let patch = component(2) else { return nil }
        return SemanticVersion(major, minor, patch)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}