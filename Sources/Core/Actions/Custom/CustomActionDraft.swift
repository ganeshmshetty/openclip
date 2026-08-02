// CustomActionDraft.swift
// OpenClip
//
// Represents a mutable draft value object used when creating or editing custom actions in UI forms.
import Foundation

public struct CustomActionDraft: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case webSearch
        case textSnippet
        case shellScript
    }

    public var title: String
    public var iconName: String
    public var kind: Kind
    public var template: String
    public var replaceSelection: Bool

    public init(
        title: String = "",
        iconName: String = "star",
        kind: Kind = .webSearch,
        template: String = "",
        replaceSelection: Bool = true
    ) {
        self.title = title
        self.iconName = iconName
        self.kind = kind
        self.template = template
        self.replaceSelection = replaceSelection
    }

    public init(action: CustomAction) {
        self.title = action.title
        self.iconName = action.iconName
        switch action.type {
        case .webSearch(let urlTemplate):
            self.kind = .webSearch
            self.template = urlTemplate
            self.replaceSelection = true
        case .textSnippet(let snippet):
            self.kind = .textSnippet
            self.template = snippet
            self.replaceSelection = true
        case .shellScript(let script, let replace):
            self.kind = .shellScript
            self.template = script
            self.replaceSelection = replace
        }
    }

    public var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty && !trimmedTemplate.isEmpty
    }

    public func toCustomAction(id: String) -> CustomAction? {
        guard isValid else { return nil }
        let type: CustomActionType
        switch kind {
        case .webSearch:
            type = .webSearch(urlTemplate: template.trimmingCharacters(in: .whitespacesAndNewlines))
        case .textSnippet:
            type = .textSnippet(template: template)
        case .shellScript:
            type = .shellScript(script: template, replaceSelection: replaceSelection)
        }
        return CustomAction(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName.isEmpty ? "star" : iconName,
            type: type
        )
    }
}
