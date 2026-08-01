import Foundation
import AppKit

@MainActor
public final class AppleIntelligenceProvider: AIProvider {
    public var type: AIProviderType { .apple }
    
    public init() {}
    
    public func process(prompt: String, text: String) async throws -> String {
        // Fallback / Stub implementation until macOS 15 system writing tools are triggered
        switch prompt.lowercased() {
        case "fix", "proofread":
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "summarize":
            return "Summary: " + text.prefix(100) + (text.count > 100 ? "..." : "")
        case "explain":
            return "Explanation of: " + text
        default:
            return "Apple Intelligence Result: " + text
        }
    }
}
