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
    var chrome: ActionChrome { get }
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult
    
    var actionOptions: [ExtensionOption] { get }
}

public extension Action {
    var isFormatting: Bool { false }
    var actionOptions: [ExtensionOption] { [] }
    var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
    }
    
    @MainActor
    var displayTitle: String {
        ActionCustomizationManager.shared.displayTitle(for: self)
    }
    
    @MainActor
    var displayIcon: ActionIcon {
        ActionCustomizationManager.shared.popupIcon(for: self)
    }
}

