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
        case .apple: return String(localized: "Apple Intelligence")
        case .ollama: return String(localized: "Ollama (Local LLM)")
        case .cloud: return String(localized: "Cloud API (OpenAI/Claude)")
        case .browser: return String(localized: "Browser Redirection")
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
    case providerUnavailable(String)
    case requestTooLarge
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return String(localized: "No text selected to process.")
        case .missingAPIKey:
            return String(localized: "API key required. Configure it in Preferences → AI.")
        case .invalidURL(let value):
            return String(localized: "Invalid URL: \(value)")
        case .invalidResponse:
            return String(localized: "The AI provider returned an empty or unreadable response.")
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return String(localized: "AI request failed (HTTP \(code)): \(body)")
            }
            return String(localized: "AI request failed (HTTP \(code)).")
        case .unsupportedModel(let model):
            return String(localized: "Model “\(model)” is not supported by the configured cloud endpoint.")
        case .providerUnavailable(let message):
            return message
        case .requestTooLarge:
            return String(localized: "Selected text is too long for this provider.")
        case .cancelled:
            return String(localized: "AI request was cancelled.")
        }
    }
}

/// AI backends that transform selected text. Marked `@MainActor` so UI can call them directly.
@MainActor
public protocol AIProvider {
    var type: AIProviderType { get }
    func process(prompt: String, text: String) async throws -> String
    func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    public func process(prompt: String, text: String) async throws -> String {
        var accumulated = ""
        for try await chunk in processStream(prompt: prompt, text: text) {
            accumulated += chunk
        }
        let result = AIRequestSupport.extractResultText(accumulated)
        guard !result.isEmpty else { throw AIError.invalidResponse }
        return result
    }
}

enum AIRequestSupport {
    /// Seconds before network AI calls time out.
    static let timeoutInterval: TimeInterval = 30

    /// Builds the system role instruction including the specific task prompt (preset or custom)
    /// while establishing the strict zero-fluff, paste-ready output contract.
    static func systemPrompt(for instruction: String) -> String {
        let task = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskSection = task.isEmpty ? "" : "\n\nTask:\n\(task)"
        return """
        You are an inline text transformation tool. Your job is to transform the user's selected text according to the task below so it can be pasted directly back into their document.\(taskSection)

        Rules:
        1. Output ONLY the transformed text.
        2. Never include conversational filler, greetings, introductions, or explanations (e.g. do NOT write "Here is the revised text:", "Sure!", or "Hope this helps").
        3. Preserve the original language, formatting, capitalization, and whitespace unless explicitly instructed to change it.
        4. For code tasks, return raw code only — do NOT wrap in markdown code fences (```) unless the original text was markdown.
        5. Wrap your final result inside <result>...</result> tags.
        """
    }

    /// Wraps the user's selected raw text in `<text>...</text>` boundaries so the model
    /// treats it strictly as input data without mixing with instruction text.
    static func userContent(for text: String) -> String {
        "<text>\n\(text)\n</text>"
    }

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
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Strip reasoning / thinking tags (<think>...</think>) from reasoning models
        if let thinkRegex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            text = thinkRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Suppress incomplete in-progress thinking block while streaming
        if let unclosedThinkRegex = try? NSRegularExpression(pattern: "^<think>[\\s\\S]*$", options: [.caseInsensitive]) {
            if unclosedThinkRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil {
                return ""
            }
        }
        
        // 2. Look for complete <result>...</result> or <output>...</output> XML tag boundaries
        let tagPatterns = [
            "<result>([\\s\\S]*?)</result>",
            "<output>([\\s\\S]*?)</output>"
        ]
        
        for pattern in tagPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                let extracted = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !extracted.isEmpty {
                    return extracted
                }
            }
        }
        
        // 3. Handle unclosed opening tag while streaming (e.g. "<result>In progress...")
        let tagPairs = [("<result>", "</result>"), ("<output>", "</output>")]
        for (openTag, closeTag) in tagPairs {
            if let openRange = text.range(of: openTag, options: .caseInsensitive) {
                if let closeRange = text.range(of: closeTag, options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
                    let inside = String(text[openRange.upperBound..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !inside.isEmpty {
                        return inside
                    }
                    // Closed but empty result/output — skip unclosed handling and fall through to fallback
                    continue
                }
                
                var afterOpen = String(text[openRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let closeRange = afterOpen.range(of: closeTag, options: .caseInsensitive) {
                    afterOpen = String(afterOpen[..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !afterOpen.isEmpty {
                    return afterOpen
                }
            }
        }
        
        return text
    }
}
