// AppleIntelligenceProvider.swift
// OpenClip
//
// Implements AI processing capabilities using local Apple Intelligence system features.
import Foundation
import AppKit

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
public final class AppleIntelligenceProvider: AIProvider {
    public var type: AIProviderType { .apple }

    public init() {}

    public func process(prompt: String, text: String) async throws -> String {
        let input = try AIRequestSupport.requireNonEmptyText(text)
        let normalizedPrompt = prompt.lowercased()

        // 1. FoundationModels native Apple Intelligence model session API
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let systemInstruction = "You are Apple Intelligence Writing Tools. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags."
                let session = LanguageModelSession(instructions: systemInstruction)
                let fullPrompt = "\(prompt):\n\n\"\(input)\""
                let response = try await session.respond(to: fullPrompt)
                let content = AIRequestSupport.extractResultText(response.content)
                if !content.isEmpty {
                    return content
                }
            } catch {
                // Model session fallback
            }
        }
        #endif

        // 2. Return raw input if on-device model is unavailable
        return input
    }
}
