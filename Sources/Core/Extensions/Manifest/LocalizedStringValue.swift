// LocalizedStringValue.swift
// OpenClip
//
// Pure Core representation of a user-facing string that can either be a plain String
// or a dictionary of localized strings keyed by language tag (e.g. "en", "zh-Hans", "zh-Hant", "fr", "ja").
import Foundation

public struct LocalizedStringValue: Codable, Sendable, Equatable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let values: [String: String]

    public init(string: String) {
        self.values = ["default": string]
    }

    public init(dictionary: [String: String]) {
        self.values = dictionary
    }

    public init(stringLiteral value: String) {
        self.init(string: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            self.values = ["default": single]
        } else if let dict = try? container.decode([String: String].self) {
            self.values = dict
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected String or [String: String] for LocalizedStringValue"
            )
        }
    }

    /// Merges additional locale mappings into this value, ensuring the base string is preserved as English/default.
    public func merging(locales: [String: String]?) -> LocalizedStringValue {
        guard let locales, !locales.isEmpty else { return self }
        var merged = values
        if let def = values["default"], merged["en"] == nil {
            merged["en"] = def
        }
        for (k, v) in locales {
            merged[k] = v
        }
        return LocalizedStringValue(dictionary: merged)
    }

    /// Combines an optional base value with an optional locale dictionary.
    public static func merge(base: LocalizedStringValue?, locales: [String: String]?) -> LocalizedStringValue? {
        if let base {
            return base.merging(locales: locales)
        } else if let locales, !locales.isEmpty {
            return LocalizedStringValue(dictionary: locales)
        }
        return nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let def = values["default"] ?? values["en"] {
            try container.encode(def)
        } else {
            try container.encode(values)
        }
    }

    /// Resolves the best string match for the given locale identifier (defaults to system/app locale).
    /// Resolution order:
    /// 1. Direct match with script (e.g. "zh-Hans", "zh-Hant")
    /// 2. Exact match on locale identifier (e.g. "fr_FR", "en_US")
    /// 3. Normalized case- and delimiter-insensitive match ("zh-hans" matches "zh_Hans")
    /// 4. Primary language code match (e.g. "fr", "ja", "en", "zh")
    /// 5. English fallback ("en", "en-US", "en_US")
    /// 6. Default key fallback ("default")
    /// 7. First available string in values
    public func resolve(for locale: Locale = .current) -> String {
        guard !values.isEmpty else { return "" }
        if let def = values["default"], values.count == 1 { return def }

        let activeTag = locale.identifier
        let langCode = locale.language.languageCode?.identifier ?? "en"
        let scriptCode = locale.language.script?.identifier

        // 1. Script tag match (crucial for Chinese zh-Hans vs zh-Hant)
        if let scriptCode {
            let scriptTagHyphen = "\(langCode)-\(scriptCode)"
            for (k, v) in values {
                let norm = k.replacingOccurrences(of: "_", with: "-")
                if norm.caseInsensitiveCompare(scriptTagHyphen) == .orderedSame {
                    return v
                }
            }
            // Region aliases: CN/SG -> zh-Hans, TW/HK -> zh-Hant
            if langCode.lowercased() == "zh" {
                if scriptCode.lowercased() == "hans" {
                    if let v = values["zh-CN"] ?? values["zh_CN"] ?? values["zh-SG"] ?? values["zh_SG"] { return v }
                } else if scriptCode.lowercased() == "hant" {
                    if let v = values["zh-TW"] ?? values["zh_TW"] ?? values["zh-HK"] ?? values["zh_HK"] { return v }
                }
            }
        }

        // 2. Exact match on full identifier
        if let val = values[activeTag] {
            return val
        }

        // 3. Normalized matching
        let normalizedActive = activeTag.lowercased().replacingOccurrences(of: "_", with: "-")
        for (k, v) in values {
            let normKey = k.lowercased().replacingOccurrences(of: "_", with: "-")
            if normKey == normalizedActive {
                return v
            }
        }

        // 4. Primary language code match (e.g. "fr", "ja", "en")
        for (k, v) in values {
            let normKey = k.lowercased().replacingOccurrences(of: "_", with: "-")
            if normKey == langCode.lowercased() {
                return v
            }
        }

        // 5. English fallback
        if let val = values["en"] ?? values["en-US"] ?? values["en_US"] {
            return val
        }

        // 6. Default key fallback
        if let val = values["default"] {
            return val
        }

        // 7. First available string
        return values.values.first ?? ""
    }

    public var description: String {
        resolve()
    }
}
