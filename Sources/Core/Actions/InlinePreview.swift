// InlinePreview.swift
// OpenClip
//
// Value shown in an inline-preview row. A string return stays plain text. An object return
// may add a swatch, tone, icon, or view-only flag. Invalid fields are dropped, never thrown.
import Foundation

public enum InlinePreviewTone: String, Sendable, Equatable {
    case `default`
    case success
    case error
    case warning

    /// Unknown names, including empty, become `.default`.
    public static func parse(_ raw: String?) -> InlinePreviewTone {
        guard let raw else { return .default }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "success": return .success
        case "error": return .error
        case "warning": return .warning
        case "default", "": return .default
        default: return .default
        }
    }
}

public struct InlinePreviewColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`. The leading `#` is optional. Anything else is nil.
    public static func parse(_ raw: String) -> InlinePreviewColor? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.first == "#" { text.removeFirst() }
        let digits = text.compactMap(Self.hexValue)
        guard digits.count == text.count else { return nil }
        let expanded: [Int]
        switch digits.count {
        case 3:
            expanded = digits.flatMap { [$0 * 16 + $0] } + [255]
        case 4:
            expanded = digits.map { $0 * 16 + $0 }
        case 6:
            expanded = stride(from: 0, to: 6, by: 2).map { digits[$0] * 16 + digits[$0 + 1] } + [255]
        case 8:
            expanded = stride(from: 0, to: 8, by: 2).map { digits[$0] * 16 + digits[$0 + 1] }
        default:
            return nil
        }
        guard expanded.count == 4 else { return nil }
        return InlinePreviewColor(
            red: Double(expanded[0]) / 255,
            green: Double(expanded[1]) / 255,
            blue: Double(expanded[2]) / 255,
            alpha: Double(expanded[3]) / 255
        )
    }

    /// Canonical hex. Opaque colors omit the alpha byte.
    public var hex: String {
        let channels = [red, green, blue, alpha].map { min(255, max(0, Int(($0 * 255).rounded()))) }
        if channels[3] == 255 {
            return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
        }
        return String(format: "#%02X%02X%02X%02X", channels[0], channels[1], channels[2], channels[3])
    }

    private static func hexValue(_ character: Character) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 48...57: return Int(ascii - 48)
        case 65...70: return Int(ascii - 65) + 10
        case 97...102: return Int(ascii - 97) + 10
        default: return nil
        }
    }
}

public enum InlinePreviewIcon: Sendable, Equatable {
    case symbol(String)
    case emoji(String)

    /// An SF Symbol name (`paintpalette` or `symbol:paintpalette`) or a short emoji. Anything else is nil.
    public static func parse(_ raw: String?) -> InlinePreviewIcon? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("symbol:") {
            return symbolName(String(trimmed.dropFirst("symbol:".count))).map { .symbol($0) }
        }
        if isEmoji(trimmed) { return .emoji(trimmed) }
        return symbolName(trimmed).map { .symbol($0) }
    }

    /// Token stored across the text-result channel. `symbol:` keeps a name distinct from an emoji.
    var transportToken: String {
        switch self {
        case .symbol(let name): return "symbol:\(name)"
        case .emoji(let emoji): return emoji
        }
    }

    private static func symbolName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64, name.contains(where: \.isLetter) else { return nil }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }) else { return nil }
        return name
    }

    private static func isEmoji(_ string: String) -> Bool {
        let characters = Array(string)
        guard (1...4).contains(characters.count) else { return false }
        return characters.allSatisfy { character in
            character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && scalar.value > 0x238C)
            }
        }
    }
}

public struct InlinePreview: Sendable, Equatable {
    public var text: String
    public var color: InlinePreviewColor?
    public var tone: InlinePreviewTone
    public var icon: InlinePreviewIcon?
    /// `false` is view-only: the row does not activate and does not highlight.
    public var actionable: Bool

    public init(
        text: String,
        color: InlinePreviewColor? = nil,
        tone: InlinePreviewTone = .default,
        icon: InlinePreviewIcon? = nil,
        actionable: Bool = true
    ) {
        self.text = text
        self.color = color
        self.tone = tone
        self.icon = icon
        self.actionable = actionable
    }

    public var acceptsActivation: Bool { actionable }

    /// Hover and keyboard-selection chrome. View-only rows stay flat.
    public func highlightFlags(hovered: Bool, selected: Bool) -> (hovered: Bool, selected: Bool) {
        guard actionable else { return (hovered: false, selected: false) }
        return (hovered: hovered, selected: selected)
    }

    var isPlain: Bool {
        color == nil && tone == .default && icon == nil && actionable
    }

    /// What `ActionResult.text` carries. A plain preview is the text itself, so existing returns are unchanged.
    public var transportText: String {
        guard !isPlain else { return text }
        var object: [String: Any] = ["text": text]
        if let color { object["color"] = color.hex }
        if tone != .default { object["tone"] = tone.rawValue }
        if let icon { object["icon"] = icon.transportToken }
        if !actionable { object["actionable"] = false }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return text
        }
        return Self.wirePrefix + json
    }

    /// A string return, or a transport payload written by an inline object return.
    /// A payload that fails to decode is shown as plain text.
    public static func resolve(returnedText: String) -> InlinePreview {
        guard returnedText.hasPrefix(wirePrefix) else {
            return InlinePreview(text: returnedText)
        }
        let json = String(returnedText.dropFirst(wirePrefix.count))
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String,
              let preview = parse(
                text: text,
                color: object["color"] as? String,
                tone: object["tone"] as? String,
                icon: object["icon"] as? String,
                actionable: jsonBool(object["actionable"])
              ) else {
            return InlinePreview(text: returnedText)
        }
        return preview
    }

    /// Builds a preview from an inline object. Nil when `text` is missing or blank.
    /// A bad color, tone, or icon is dropped and the text remains.
    public static func parse(
        text: String?,
        color: String?,
        tone: String?,
        icon: String?,
        actionable: Bool?
    ) -> InlinePreview? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return InlinePreview(
            text: text,
            color: color.flatMap(InlinePreviewColor.parse),
            tone: InlinePreviewTone.parse(tone),
            icon: InlinePreviewIcon.parse(icon),
            actionable: actionable ?? true
        )
    }

    /// Private-use marker so a rich payload can cross `ActionResult.text` without looking like a user's string.
    private static let wirePrefix = "\u{E000}openclip.inline:"

    private static func jsonBool(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return nil
        default:
            return nil
        }
    }
}
