import Foundation

@MainActor
public final class CustomActionManager: Sendable {
    public static let shared = CustomActionManager()
    
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
                ActionRegistry.shared.register(action: action)
            }
        } catch {
            print("Failed to load custom actions: \(error)")
        }
    }
    
    public func register(customAction: CustomAction) {
        customActions.removeAll(where: { $0.id == customAction.id })
        customActions.append(customAction)
        ActionRegistry.shared.register(action: customAction)
        save()
    }
    
    public func delete(customActionID: String) {
        customActions.removeAll(where: { $0.id == customActionID })
        // Note: ActionRegistry currently only supports adding actions.
        // In a real app we'd need a way to unregister them from ActionRegistry.shared.
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
