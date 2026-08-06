// CalculateAction.swift
// OpenClip
//
// Implements the builtin math expression evaluation action, computing mathematical expressions found in selected text.
// Conforms to ResultContentProviding to surface a result card (on long-press) with per-click delivery options
// (paste/copy), superseding the global calculateMode setting for the result-card path.
import Foundation

public struct CalculateAction: ConfigurableAction, ResultContentProviding {
    public let id = "builtin.calculate"
    public var title: String { "Calculate" }
    public let configurationViewID = "builtin.calculate"
    public let preferenceIconName = "equal.circle"
    public let icon = ActionIcon.symbol("equal.circle")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && text.count <= 200 else { return false }
        
        // Must contain math operators to trigger calculation
        let hasMathOperator = text.contains("+") || text.contains("-") || text.contains("*") || text.contains("/") || text.contains("%")
        guard hasMathOperator else { return false }
        
        return evaluateExpression(text) != nil
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result = evaluateExpression(text) {
            let resultString = formatResult(result)
            let mode = DefaultSettingsStore.shared.get(.calculateMode)

            
            switch mode {
            case "copy":
                return .copy(resultString)
            case "append":
                return .paste("\(text) = \(resultString)")
            case "paste":
                fallthrough
            default:
                return .paste(resultString)
            }
        }
        return .none
    }
    
    // MARK: - ResultContentProviding

    @MainActor
    public func makeContent(for context: ActionContext) async -> PopupContent? {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = evaluateExpression(text) else { return nil }
        let resultString = formatResult(result)
        let fullLine = "\(text) = \(resultString)"

        return PopupContent(
            title: "Calculate",
            icon: preferenceIconName,
            subtitle: fullLine,
            rows: [.text(resultString)],
            footer: [
                ContentOption(
                    title: "Paste \(resultString)",
                    subtitle: "Replace selection with result",
                    icon: "arrow.triangle.2.circlepath",
                    outcome: .perform(.paste(resultString))
                ),
                ContentOption(
                    title: "Copy \(resultString)",
                    subtitle: "Copy result to clipboard",
                    icon: "doc.on.doc",
                    outcome: .perform(.copy(resultString))
                ),
                ContentOption(
                    title: "Copy \(fullLine)",
                    subtitle: "Copy expression and result",
                    icon: "doc.on.doc.fill",
                    outcome: .perform(.copy(fullLine))
                )
            ],
            emphasis: .result
        )
    }
    
    private func evaluateExpression(_ text: String) -> Double? {
        // Sanitize string to allow standard math symbols
        let sanitized = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure string only contains digits, math operators, spaces, parentheses, and dots
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%() ")
        guard !sanitized.isEmpty,
              sanitized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        // MathEvaluator parses deterministically and returns nil for malformed input; NSExpression
        // used to throw an uncaught Objective-C exception here (e.g. on a bare "+" selection).
        return MathEvaluator.evaluate(sanitized)
    }
    
    private func formatResult(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            var result = String(format: "%.4f", value)
            while result.hasSuffix("0") {
                result.removeLast()
            }
            if result.hasSuffix(".") {
                result.removeLast()
            }
            return result
        }
    }
}
