import Foundation

public struct CalculateAction: ConfigurableAction {
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
    
    private func evaluateExpression(_ text: String) -> Double? {
        // Sanitize string to allow standard math symbols
        let sanitized = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure string only contains digits, math operators, spaces, parentheses, and dots
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%() ")
        guard sanitized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        
        let expression = NSExpression(format: sanitized)
        guard let value = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }
        return value.doubleValue
    }
    
    private func formatResult(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.4f", value).replacingOccurrences(of: "(?<=\\.\\d{2})0+$", with: "", options: .regularExpression)
        }
    }
}
