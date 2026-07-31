import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct SearchAction: Action {
    public let id = "builtin.search"
    public let title = "Search"
    public let icon = ActionIcon.symbol("magnifyingglass")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let query = context.selection.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = String(format: Constants.searchURLTemplate, query)
        if let url = URL(string: urlString) {
            return .openURL(url)
        }
        return .failure(NSError(domain: "SearchAction", code: 1, userInfo: nil))
    }
}
