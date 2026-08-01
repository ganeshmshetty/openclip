import Foundation

public enum AIProviderType: String, CaseIterable, Identifiable {
    case apple = "apple"
    case ollama = "ollama"
    case cloud = "cloud"
    case browser = "browser"

    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .ollama: return "Ollama (Local LLM)"
        case .cloud: return "Cloud API (OpenAI/Claude)"
        case .browser: return "Browser Redirection"
        }
    }
}

@MainActor
public protocol AIProvider {
    var type: AIProviderType { get }
    func process(prompt: String, text: String) async throws -> String
}
