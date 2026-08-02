// ActionPresentation.swift
// OpenClip
//
// Serves as the Look Door for resolving action display titles and icons tailored for specific UI surfaces.
// Adapts presentation models for popup and preferences table views, taking user overrides into account.
import Foundation
import Combine

public enum ActionPresentationSurface: Sendable {
    case popup
    case table
}

public struct ActionPresentationModel: Sendable, Equatable {
    public let title: String
    public let icon: ActionIcon

    public init(title: String, icon: ActionIcon) {
        self.title = title
        self.icon = icon
    }
}

@MainActor
public final class ActionPresentation: ObservableObject, Sendable {
    public static let shared = ActionPresentation()
    private let customizationManager: ActionCustomizationManager

    public init(customizationManager: ActionCustomizationManager = .shared) {
        self.customizationManager = customizationManager
    }

    public func presented(_ action: any Action, surface: ActionPresentationSurface) -> ActionPresentationModel {
        let title = customizationManager.displayTitle(for: action)
        let icon: ActionIcon
        switch surface {
        case .popup:
            icon = customizationManager.popupIcon(for: action)
        case .table:
            icon = customizationManager.tableIcon(for: action)
        }
        return ActionPresentationModel(title: title, icon: icon)
    }

    public func setOverride(for actionID: String, title: String?, symbol: String?, text: String?) {
        customizationManager.setOverride(for: actionID, title: title, symbol: symbol, text: text)
    }

    public func resetOverride(for actionID: String) {
        customizationManager.resetOverride(for: actionID)
    }
}
