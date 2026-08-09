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
    public let preferenceIconName = "equal.circle"
    public let icon = ActionIcon.symbol("equal.circle")
    
    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
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
            let mode = settingsStore.get(.calculateMode)

            
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
    public func makeContent(for context: ActionContext) async -> CanvasComponent? {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result = evaluateExpression(text) else { return nil }
        let resultString = formatResult(result)
        let fullLine = "\(text) = \(resultString)"

        return Canvas.build {
            Canvas.text(fullLine)
            Canvas.button("Paste \(resultString)", icon: .symbol("arrow.triangle.2.circlepath"), handler: .effect(.paste(resultString)))
            Canvas.button("Copy \(resultString)", icon: .symbol("doc.on.doc"), handler: .effect(.copy(resultString)))
            Canvas.button("Copy \(fullLine)", icon: .symbol("doc.on.doc.fill"), handler: .effect(.copy(fullLine)))
        }
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
