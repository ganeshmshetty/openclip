// AIProvider.swift
// OpenClip
//
// Defines the protocol and model types for integrating AI model providers into OpenClip selection processing.
import Foundation
import Core

public enum AIProviderType: String, CaseIterable, Identifiable, Sendable {
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

public enum AIError: Error, LocalizedError, Sendable, Equatable {
    case emptyInput
    case missingAPIKey
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case unsupportedModel(String)
    case requestTooLarge
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No text selected to process."
        case .missingAPIKey:
            return "API key required. Configure it in Preferences → AI."
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .invalidResponse:
            return "The AI provider returned an empty or unreadable response."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "AI request failed (HTTP \(code)): \(body)"
            }
            return "AI request failed (HTTP \(code))."
        case .unsupportedModel(let model):
            return "Model “\(model)” is not supported by the configured cloud endpoint."
        case .requestTooLarge:
            return "Selected text is too long for this provider."
        case .cancelled:
            return "AI request was cancelled."
        }
    }
}

/// AI backends that transform selected text. Marked `@MainActor` so UI can call them directly.
@MainActor
public protocol AIProvider {
    var type: AIProviderType { get }
    func process(prompt: String, text: String) async throws -> String
}

enum AIRequestSupport {
    /// Seconds before network AI calls time out.
    static let timeoutInterval: TimeInterval = 30

    /// System role/instruction every provider receives: perform the requested edit on the user's
    /// text and wrap the final result in `<result>...</result>` tags (which `extractResultText`
    /// strips). Defined once so the cloud and local providers can't drift.
    static let systemPrompt = "You are an inline text editing tool. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags."

    /// Query-value encoding that escapes `&`, `=`, `?`, etc. (stricter than `.urlQueryAllowed`).
    static var queryValueAllowed: CharacterSet {
        Constants.queryValueAllowed
    }

    static func requireNonEmptyText(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyInput }
        return trimmed
    }

    static func normalizedBaseURL(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    static func httpErrorMessage(status: Int, data: Data) -> AIError {
        let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = body.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
        return .httpStatus(status, snippet)
    }

    static func extractResultText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for <result>...</result> or <output>...</output> XML tag boundaries
        let tagPatterns = [
            "<result>([\\s\\S]*?)</result>",
            "<output>([\\s\\S]*?)</output>"
        ]
        
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: trimmed) {
                let extracted = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    return extracted
                }
            }
        }
        
        return trimmed
    }}
