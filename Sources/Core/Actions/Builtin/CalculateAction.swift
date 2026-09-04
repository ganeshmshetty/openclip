// CalculateAction.swift
// OpenClip
//
// Implements the builtin math expression evaluation action, computing mathematical expressions found in selected text.
import Foundation

public struct CalculateAction: ConfigurableAction {
    public let id = "builtin.calculate"
    public var title: String { String(localized: "Calculate") }
    public let preferenceIconName = "equal.circle"
    public let icon = ActionIcon.symbol("equal.circle")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && text.count <= 200 else { return false }
        
        guard let sanitized = sanitize(text), containsMathIntent(sanitized) else { return false }
        return evaluateExpression(sanitized) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sanitized = sanitize(text),
              let result = evaluateExpression(sanitized) else {
            return .none
        }
        let resultString = formatResult(result)
        return .text(resultString)
    }
    
    private func sanitize(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip common currency symbols
        let currencies = ["$", "€", "£", "¥", "₹", "₩", "₽", "฿", "¢"]
        for sym in currencies {
            s = s.replacingOccurrences(of: sym, with: "")
        }
        
        // Strip trailing/leading equals signs and question marks
        s = s.replacingOccurrences(of: "=", with: " ")
             .replacingOccurrences(of: "?", with: " ")

        // Normalize unicode multiplication & division
        s = s.replacingOccurrences(of: "×", with: "*")
             .replacingOccurrences(of: "÷", with: "/")
             .replacingOccurrences(of: "·", with: "*")

        // Normalize unicode dashes & minus signs (macOS smart dashes)
        s = s.replacingOccurrences(of: "–", with: "-") // En-dash
             .replacingOccurrences(of: "—", with: "-") // Em-dash
             .replacingOccurrences(of: "−", with: "-") // Unicode minus

        // Normalize letter x / X as multiplication when surrounded by whitespace: "5 x 10" -> "5 * 10"
        s = s.replacingOccurrences(of: " x ", with: " * ")
             .replacingOccurrences(of: " X ", with: " * ")

        // Normalize decimal & thousands separators intelligently
        s = normalizeSeparators(s)

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Allowed character set (digits, operators, parens, dot, percent, power, spaces)
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%^() ")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        return s
    }

    /// Intelligently resolves decimal points and thousands separators across US (1,250.50)
    /// and European (1.250,50 / 12,5 + 3,5) math expressions without requiring manual settings.
    private func normalizeSeparators(_ text: String) -> String {
        guard text.contains(",") else { return text }

        guard let regex = try? NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)+"#) else {
            return text
        }

        var s = text
        let nsString = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length))
        guard !matches.isEmpty else { return s }

        let isSystemCommaDecimal = Locale.current.decimalSeparator == ","

        for match in matches.reversed() {
            let tokenRange = match.range
            guard let swiftRange = Range(tokenRange, in: s) else { continue }
            let token = String(s[swiftRange])
            guard token.contains(",") else { continue }

            let normalizedToken: String
            if token.contains(".") {
                // Contains both '.' and ','
                if let lastDot = token.lastIndex(of: "."),
                   let lastComma = token.lastIndex(of: ","),
                   lastDot < lastComma {
                    // Dot precedes comma: European style ("1.250,50" -> "1250.50")
                    var t = token.replacingOccurrences(of: ".", with: "")
                    t = t.replacingOccurrences(of: ",", with: ".")
                    normalizedToken = t
                } else {
                    // Comma precedes dot: US style ("1,250.50" -> "1250.50")
                    normalizedToken = token.replacingOccurrences(of: ",", with: "")
                }
            } else {
                // Contains only ','
                let parts = token.split(separator: ",")
                if parts.count > 2 {
                    // Multiple commas: e.g. "1,000,000"
                    normalizedToken = token.replacingOccurrences(of: ",", with: "")
                } else if parts.count == 2 {
                    let intPart = parts[0]
                    let fracPart = parts[1]
                    // Precedence heuristic: If exactly 3 fractional digits and non-zero integer on a
                    // period-decimal locale (e.g. US "1,250"), assume comma is a thousands separator ("1250").
                    // Otherwise (e.g. European "12,5" or "0,250"), normalize comma to decimal period ("12.5").
                    if fracPart.count != 3 || intPart == "0" || isSystemCommaDecimal {
                        normalizedToken = "\(intPart).\(fracPart)"
                    } else {
                        normalizedToken = token.replacingOccurrences(of: ",", with: "")
                    }
                } else {
                    normalizedToken = token.replacingOccurrences(of: ",", with: ".")
                }
            }

            s.replaceSubrange(swiftRange, with: normalizedToken)
        }

        return s
    }

    private func containsMathIntent(_ text: String) -> Bool {
        let operators = CharacterSet(charactersIn: "+-*/%^()")
        return text.unicodeScalars.contains { operators.contains($0) }
    }

    private func evaluateExpression(_ sanitized: String) -> Double? {
        return MathEvaluator.evaluate(sanitized)
    }
    
    private func formatResult(_ value: Double) -> String {
        if value.isInfinite || value.isNaN {
            return ""
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1e15 {
            return String(format: "%.0f", value)
        } else {
            var result = String(format: "%.6f", value)
            while result.contains(".") && result.hasSuffix("0") {
                result.removeLast()
            }
            if result.hasSuffix(".") {
                result.removeLast()
            }
            return result
        }
    }
}
