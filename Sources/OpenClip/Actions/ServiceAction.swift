import Foundation
import AppKit
import Core

@MainActor
public struct ServiceAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let serviceName: String
    
    public init(id: String, title: String, iconSymbol: String = "gearshape.2.fill", serviceName: String) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconSymbol)
        self.serviceName = serviceName
    }
    
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let pboard = NSPasteboard.withUniqueName()
        pboard.clearContents()
        pboard.setString(context.selection.text, forType: .string)
        
        let success = NSPerformService(serviceName, pboard)
        if success {
            return .success
        } else {
            return .failure(NSError(domain: "ServiceAction", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to perform macOS service: \(serviceName)"]))
        }
    }
}
