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
    private let storageKey = "action.customizations"
    
    private init() {
        loadOverrides()
    }
    
    public func loadOverrides() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
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
    
    private func saveOverrides() {
        if let encoded = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
