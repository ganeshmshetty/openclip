import Foundation

public enum ActionIcon: Sendable, Equatable {
    case symbol(String)
    case url(URL)
    case local(URL)
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
}
