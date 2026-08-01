import Foundation

public enum ActionIcon: Sendable, Equatable {
    case symbol(String)
    case url(URL)
    case local(URL)
    case text(String)
}

public protocol Action: Sendable {
    var id: String { get }
    var title: String { get }
    var icon: ActionIcon { get }
    var isFormatting: Bool { get }
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult
}

public extension Action {
    var isFormatting: Bool { false }
    
    @MainActor
    var displayTitle: String {
        ActionCustomizationManager.shared.override(for: id)?.customTitle ?? title
    }
    
    @MainActor
    var displayIcon: ActionIcon {
        if let override = ActionCustomizationManager.shared.override(for: id) {
            if let text = override.customIconText, !text.isEmpty {
                return .text(text)
            }
            if let symbol = override.customIconSymbol, !symbol.isEmpty {
                return .symbol(symbol)
            }
        }
        return icon
    }
}
