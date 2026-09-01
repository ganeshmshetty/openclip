// CustomGroupAction.swift
// OpenClip
//
// Pure domain model representing a custom user-defined action group row.
// Conforms to Action and SubActionProviding, resolving subactions from the catalog by canonical ID.
import Foundation

public struct CustomGroupAction: Action, SubActionProviding, Sendable {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let chrome: ActionChrome
    public let memberActionIDs: [String]

    public init(id: String, title: String, iconName: String, memberActionIDs: [String]) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconName)
        self.chrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        self.memberActionIDs = memberActionIDs
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        nil
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .none
    }

    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        let memberSet = Set(memberActionIDs)
        return catalog.filter { memberSet.contains($0.id) }
    }
}
