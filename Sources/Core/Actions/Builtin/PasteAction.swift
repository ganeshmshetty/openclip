import Foundation

public struct PasteAction: ConfigurableAction {
    public let id = "builtin.paste"
    public let title = "Paste"
    public let configurationViewID = "builtin.paste"
    public let preferenceIconName = "clipboard"
    public var icon: ActionIcon {
        if UserDefaults.standard.bool(forKey: "action.paste.useText") {
            return .text("Paste")
        }
        return .symbol("clipboard")
    }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return true
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .simulatePaste
    }
}
