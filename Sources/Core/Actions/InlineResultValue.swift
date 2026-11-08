// InlineResultValue.swift
// OpenClip
//
// Platform-independent typed inline result values: text and normalized sRGB color.
// Presentation (fonts, swatches, layout) lives in the app target; this file owns validation,
// canonicalization, bounds, and delivery capability.
import Foundation

/// A validated `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA` color in sRGB.
public struct InlineColor: Sendable, Equatable, Hashable {
    /// Canonical uppercase `#RRGGBB` when opaque, `#RRGGBBAA` otherwise.
    public let hex: String
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init?(hex raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }

        let components: (Double, Double, Double, Double)
        switch digits.count {
        case 3:
            components = Self.expand(digits, alpha: false)
        case 4:
            components = Self.expand(digits, alpha: true)
        case 6:
            let r = Self.byte(digits, 0)
            let g = Self.byte(digits, 2)
            let b = Self.byte(digits, 4)
            components = (Double(r) / 255, Double(g) / 255, Double(b) / 255, 1)
        case 8:
            let r = Self.byte(digits, 0)
            let g = Self.byte(digits, 2)
            let b = Self.byte(digits, 4)
            let a = Self.byte(digits, 6)
            components = (Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
        default:
            return nil
        }

        self.red = components.0
        self.green = components.1
        self.blue = components.2
        self.alpha = components.3
        self.hex = Self.canonicalHex(red: components.0, green: components.1, blue: components.2, alpha: components.3)
    }

    private static func expand(_ digits: Substring, alpha: Bool) -> (Double, Double, Double, Double) {
        let values = digits.map { Double(Int(String($0), radix: 16) ?? 0) / 15 }
        return (values[0], values[1], values[2], alpha ? values[3] : 1)
    }

    private static func byte(_ digits: Substring, _ offset: Int) -> Int {
        let start = digits.index(digits.startIndex, offsetBy: offset)
        let end = digits.index(start, offsetBy: 2)
        return Int(digits[start..<end], radix: 16) ?? 0
    }

    private static func canonicalHex(red: Double, green: Double, blue: Double, alpha: Double) -> String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        let base = String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
        guard channel(alpha) < 255 else { return base }
        return base + String(format: "%02X", channel(alpha))
    }
}

/// The value an inline action returns: display data, never display instructions.
public enum InlineResultValue: Sendable, Equatable, Hashable {
    case text(String)
    case color(InlineColor)

    /// The release that introduced typed inline values and `displayOnly`.
    public static let minimumOpenClipVersion = "1.10.0"

    public static let maxAutomaticTextUTF8Bytes = 64 * 1024
    public static let maxDisplayOnlyTextGraphemes = 256
    public static let maxDisplayOnlyTextUTF8Bytes = 4 * 1024

    /// Builds and validates a typed value. `nil` means the value is not an inline result.
    /// `displayOnly` applies the tighter informational-text bounds.
    public static func make(type: String, value: String, displayOnly: Bool) -> InlineResultValue? {
        switch type.lowercased() {
        case "text":
            return makeText(value, displayOnly: displayOnly)
        case "color":
            guard let color = InlineColor(hex: value) else { return nil }
            return .color(color)
        default:
            return nil
        }
    }

    public static func makeText(_ value: String, displayOnly: Bool = false) -> InlineResultValue? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let utf8 = value.utf8.count
        if displayOnly {
            guard utf8 <= maxDisplayOnlyTextUTF8Bytes,
                  value.count <= maxDisplayOnlyTextGraphemes else { return nil }
        } else {
            guard utf8 <= maxAutomaticTextUTF8Bytes else { return nil }
        }
        return .text(value)
    }

    /// The complete value used for Paste/Copy and the card; never a truncated label.
    public var rawValue: String {
        switch self {
        case .text(let value):
            return value
        case .color(let color):
            return color.hex
        }
    }

    /// One-line representation: line breaks and tabs collapse to spaces; the stored value is untouched.
    public var displayText: String {
        switch self {
        case .text(let value):
            return value
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
        case .color:
            return rawValue
        }
    }

    public var kind: ExtensionOutputKind {
        switch self {
        case .text: return .text
        case .color: return .color
        }
    }

    public var inlineActionResult: ActionResult {
        switch self {
        case .text(let value):
            return .text(value)
        case .color(let color):
            return .color(color)
        }
    }

    /// Coerces an untyped JavaScript string return using the action's declared inline output.
    /// A legacy inline action (no declared output) stays text; a declared color validates the string.
    public static func makeLegacyString(
        _ value: String,
        for output: ExtensionOutputKind,
        displayOnly: Bool
    ) -> InlineResultValue? {
        switch output {
        case .file:
            return nil
        case .color:
            guard let color = InlineColor(hex: value) else { return nil }
            return .color(color)
        default:
            return makeText(value, displayOnly: displayOnly)
        }
    }

    /// Whether a decoded value is compatible with the action's declared inline output.
    /// Legacy inline actions declare `.text`, so a typed color is a mismatch, not a reinterpretation.
    public func matches(declaredOutput: ExtensionOutputKind) -> Bool {
        switch declaredOutput {
        case .text, .dynamic, .none:
            return kind == .text
        case .color:
            return kind == .color
        case .file:
            return false
        }
    }
}
