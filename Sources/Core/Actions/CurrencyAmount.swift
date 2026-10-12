import Foundation

/// A single monetary literal. Recognition never fetches rates or examines other application data.
public struct CurrencyAmount: Equatable, Sendable {
    public let value: Decimal
    public let code: String
    public let assumedDollar: Bool

    public static let supportedCodes = Locale.commonISOCurrencyCodes.sorted()

    public static func parse(_ input: String, dollarCurrency: String = "USD", locale: Locale = .current) -> Self? {
        guard input.count <= 200 else { return nil }
        let ignored: Set<Unicode.Scalar> = ["\u{200e}", "\u{200f}", "\u{061c}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        var text = String(String.UnicodeScalarView(input.unicodeScalars.filter { !ignored.contains($0) }))
        text = String(text.map { character in
            if let digit = character.wholeNumberValue, digit < 10 { return Character(String(digit)) }
            return character == "−" ? "-" : character
        }).trimmingCharacters(in: .whitespacesAndNewlines)
        // Permit the sign before a currency symbol as well as before the number.
        var leadingSign = ""
        if let first = text.first, first == "-" || first == "+" {
            leadingSign = String(text.removeFirst())
            text = text.trimmingCharacters(in: .whitespaces)
        }
        let aliases: [(String, String)] = [
            ("ريال سعودي", "SAR"), ("دولار أمريكي", "USD"), ("ر.س", "SAR"),
            ("د.إ", "AED"), ("CA$", "CAD"), ("C$", "CAD"), ("AU$", "AUD"),
            ("A$", "AUD"), ("NZ$", "NZD"), ("HK$", "HKD"), ("SG$", "SGD"),
            ("US$", "USD"), ("€", "EUR"), ("£", "GBP"), ("₹", "INR"),
            ("$", dollarCurrency)
        ]
        var code: String?
        var assumed = false
        for (alias, currency) in aliases {
            if text.lowercased().hasPrefix(alias.lowercased()) {
                text.removeFirst(alias.count); code = currency; assumed = alias == "$"; break
            }
            if text.lowercased().hasSuffix(alias.lowercased()) {
                text.removeLast(alias.count); code = currency; assumed = alias == "$"; break
            }
        }
        if code == nil {
            let prefix = String(text.prefix(3)).uppercased()
            let suffix = String(text.suffix(3)).uppercased()
            if supportedCodes.contains(prefix) { code = prefix; text.removeFirst(3) }
            else if supportedCodes.contains(suffix) { code = suffix; text.removeLast(3) }
        }
        guard let code, supportedCodes.contains(code) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = leadingSign + text
        // Normalize explicit Arabic separators before considering locale-dependent punctuation.
        let arabicDecimal = text.contains("٫")
        text = text.replacingOccurrences(of: "٬", with: ",").replacingOccurrences(of: "٫", with: ".")
        guard text.range(of: #"^[+-]?[0-9][0-9., \u00a0\u202f]*$"#, options: .regularExpression) != nil else { return nil }
        // A space separator must separate full groups of three, never two independent amounts.
        if text.contains(where: { $0.isWhitespace }) {
            guard text.range(of: #"^[+-]?[0-9]{1,3}(?:[ \u00a0\u202f][0-9]{3})+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            text.removeAll(where: { $0.isWhitespace })
        }
        let decimal: Character?
        if text.contains(","), text.contains(".") {
            decimal = text.lastIndex(of: ",")! > text.lastIndex(of: ".")! ? "," : "."
        } else if let separator: Character = text.contains(",") ? "," : (text.contains(".") ? "." : nil) {
            let chunks = text.split(separator: separator, omittingEmptySubsequences: false)
            if chunks.count > 2 { decimal = nil }
            else if arabicDecimal || chunks.last?.count != 3 { decimal = separator }
            else { decimal = String(separator) == locale.decimalSeparator ? separator : nil }
        } else { decimal = nil }
        let parts = decimal.map { text.split(separator: $0, omittingEmptySubsequences: false).map(String.init) } ?? [text]
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let integer = parts[0]
        let grouping: Character? = integer.contains(",") ? "," : (integer.contains(".") ? "." : nil)
        if let grouping {
            let escaped = NSRegularExpression.escapedPattern(for: String(grouping))
            guard integer.range(of: "^[+-]?[0-9]{1,3}(?:" + escaped + "[0-9]{3})+$", options: .regularExpression) != nil else { return nil }
        }
        let normalizedInteger = integer.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
        if parts.count == 2, !parts[1].allSatisfy(\.isNumber) { return nil }
        let normalized = normalizedInteger + (parts.count == 2 ? "." + parts[1] : "")
        guard normalized.filter(\.isNumber).count <= 28,
              let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
        return Self(value: value, code: code, assumedDollar: assumed)
    }
}

public struct CurrencyRate: Codable, Equatable, Sendable {
    public let date: String
    public let base: String
    public let quote: String
    public let rate: Decimal

    public init(date: String, base: String, quote: String, rate: Decimal) {
        self.date = date; self.base = base; self.quote = quote; self.rate = rate
    }

    public var observationDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let value = formatter.date(from: date), formatter.string(from: value) == date else { return nil }
        return value
    }

    public func isUsable(at now: Date) -> Bool {
        guard rate > 0, !rate.isNaN, let date = observationDate else { return false }
        return date <= now && now.timeIntervalSince(date) <= 7 * 86_400
    }

    /// Table has the destination as base. The selected source is its quote, so divide once.
    public func convert(_ amount: CurrencyAmount, at now: Date) -> Decimal? {
        guard amount.code == quote, isUsable(at: now) else { return nil }
        var value = amount.value
        var divisor = rate
        var result = Decimal()
        let error = NSDecimalDivide(&result, &value, &divisor, .plain)
        guard error == .noError || error == .lossOfPrecision, !result.isNaN else { return nil }
        return result
    }
}
