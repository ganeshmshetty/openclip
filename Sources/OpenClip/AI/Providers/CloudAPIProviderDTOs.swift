// CloudAPIProviderDTOs.swift
// OpenClip
//
// Codable request/response payloads for the OpenAI-compatible, Anthropic, and Gemini
// chat APIs used by CloudAPIProvider. Split out of CloudAPIProvider.swift.
import Foundation

struct OpenAIChatRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let stream: Bool?

    init(model: String, messages: [Message], stream: Bool? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

struct OpenAIChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}

struct AnthropicMessagesRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    let stream: Bool?

    init(model: String, maxTokens: Int, system: String?, messages: [Message], stream: Bool? = nil) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case stream
    }
}

struct AnthropicMessagesResponse: Decodable, Sendable {
    struct ContentBlock: Decodable, Sendable {
        let type: String?
        let text: String?
    }
    let content: [ContentBlock]?
}

struct GeminiChatRequest: Encodable, Sendable {
    struct Part: Encodable, Sendable {
        let text: String
    }
    struct Content: Encodable, Sendable {
        let parts: [Part]
    }
    struct SystemInstruction: Encodable, Sendable {
        let parts: [Part]
    }

    let systemInstruction: SystemInstruction?
    let contents: [Content]

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
    }
}

struct GeminiChatResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            struct Part: Decodable, Sendable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
