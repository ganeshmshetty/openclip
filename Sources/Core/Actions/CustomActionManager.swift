// CustomActionManager.swift
// OpenClip
//
// Manages the persistence and lifecycle of user-defined custom actions.
// Performs its own file I/O for custom_actions.json and reports changes to the
// ActionRegistry via the onRegister/onUnregister callbacks that
// ActionCoordinator.loadInitialState() wires. Does not touch ActionRegistry directly.
import Foundation

@MainActor
public final class CustomActionManager: Sendable {
    public static let shared = CustomActionManager()
    
    /// Wired by `ActionCoordinator.loadInitialState()`; the manager never touches the registry directly.
    public var onRegister: ((any Action) -> Void)?
    public var onUnregister: ((String) -> Void)?
    
    public private(set) var customActions: [CustomAction] = []
    
    private init() {
    }
    
    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let openClipDir = appSupport.appendingPathComponent("OpenClip")
        if !FileManager.default.fileExists(atPath: openClipDir.path) {
            try? FileManager.default.createDirectory(at: openClipDir, withIntermediateDirectories: true)
        }
        return openClipDir.appendingPathComponent("custom_actions.json")
    }
    
    public func load() {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let actions = try JSONDecoder().decode([CustomAction].self, from: data)
            self.customActions = actions
            for action in actions {
                onRegister?(action)
            }
        } catch {
            print("Failed to load custom actions: \(error)")
        }
    }
    
    public func register(customAction: CustomAction) {
        customActions.removeAll(where: { $0.id == customAction.id })
        customActions.append(customAction)
        onRegister?(customAction)
        save()
    }
    
    public func delete(customActionID: String) {
        customActions.removeAll(where: { $0.id == customActionID })
        onUnregister?(customActionID)
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(customActions)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save custom actions: \(error)")
        }
    }
}
