// CalculateAction.swift
// OpenClip
//
// Implements the builtin math expression evaluation action, computing mathematical expressions found in selected text.
import Foundation

public struct CalculateAction: ConfigurableAction {
    public let id = "builtin.calculate"
    public var title: String { "Calculate" }
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

        // Normalize comma as thousands separator
        s = s.replacingOccurrences(of: ",", with: "")

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Allowed character set (digits, operators, parens, dot, percent, power, spaces)
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%^() ")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

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
