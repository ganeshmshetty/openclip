// ActionCustomizationManager.swift
// OpenClip
//
// Manages user-configured overrides for action titles and icons, persisting customizations via the Settings Door.
// Provides display title and icon resolution for popup and table surfaces based on user preferences.
import Foundation
import Combine

public struct ActionOverride: Codable, Sendable, Equatable {
    public var customTitle: String?
    public var customIconSymbol: String?
    public var customIconText: String?
    
    public init(customTitle: String? = nil, customIconSymbol: String? = nil, customIconText: String? = nil) {
        self.customTitle = customTitle
        self.customIconSymbol = customIconSymbol
        self.customIconText = customIconText
    }
}

@MainActor
public final class ActionCustomizationManager: ObservableObject, Sendable {
    public static let shared = ActionCustomizationManager()
    
    @Published public private(set) var overrides: [String: ActionOverride] = [:]
    private let settingsStore: SettingsStore
    
    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        loadOverrides()
    }
    
    public func loadOverrides() {
        if let data = settingsStore.get(.actionCustomizations),
           let decoded = try? JSONDecoder().decode([String: ActionOverride].self, from: data) {
            self.overrides = decoded
        } else {
            self.overrides = [:]
        }
    }
    
    public func override(for actionID: String) -> ActionOverride? {
        return overrides[actionID]
    }
    
    public func setOverride(for actionID: String, title: String?, symbol: String?, text: String?) {
        var existing = overrides[actionID] ?? ActionOverride()
        
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.customTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        
        let trimmedSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.customIconSymbol = (trimmedSymbol?.isEmpty == false) ? trimmedSymbol : nil
        
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.customIconText = (trimmedText?.isEmpty == false) ? trimmedText : nil
        
        if existing.customTitle == nil && existing.customIconSymbol == nil && existing.customIconText == nil {
            overrides.removeValue(forKey: actionID)
        } else {
            overrides[actionID] = existing
        }
        
        saveOverrides()
    }
    
    public func resetOverride(for actionID: String) {
        overrides.removeValue(forKey: actionID)
        saveOverrides()
    }
    
    // MARK: - Centralized Presentation Resolvers

    public func displayTitle(for action: any Action) -> String {
        let ov = override(for: action.id)
        if let customTitle = ov?.customTitle, !customTitle.isEmpty {
            return customTitle
        }
        return action.title
    }

    public func popupIcon(for action: any Action) -> ActionIcon {
        let ov = override(for: action.id)
        if let text = ov?.customIconText, !text.isEmpty {
            return .text(text)
        }
        if let symbol = ov?.customIconSymbol, !symbol.isEmpty {
            return .symbol(symbol)
        }
        return action.icon
    }

    public func tableIcon(for action: any Action) -> ActionIcon {
        let ov = override(for: action.id)
        if let symbol = ov?.customIconSymbol, !symbol.isEmpty {
            return .symbol(symbol)
        }
        if let configurable = action as? any ConfigurableAction {
            return .symbol(configurable.preferenceIconName)
        }
        switch action.id {
        case "builtin.copy": return .symbol("doc.on.doc")
        case "builtin.cut": return .symbol("scissors")
        case "builtin.paste": return .symbol("doc.on.clipboard")
        case "builtin.define": return .symbol("character.book.closed")
        default:
            return action.icon
        }
    }

    private func saveOverrides() {
        if let encoded = try? JSONEncoder().encode(overrides) {
            settingsStore.set(.actionCustomizations, value: encoded)
        }
    }
}

