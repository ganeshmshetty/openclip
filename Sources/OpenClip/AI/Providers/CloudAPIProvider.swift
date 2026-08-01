import Foundation

@MainActor
public final class CloudAPIProvider: AIProvider {
    public var type: AIProviderType { .cloud }
    
    public let apiKey: String
    public let model: String
    
    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? "gpt-4o-mini" : model
    }
    
    public func process(prompt: String, text: String) async throws -> String {
        guard !apiKey.isEmpty else {
            return "[API Key Required] Please configure your OpenAI/Claude API Key in Preferences > AI."
        }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a helpful assistant for quick text editing."],
            ["role": "user", "content": "\(prompt): \(text)"]
        ]
        let body: [String: Any] = [
            "model": model,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let messageObj = firstChoice["message"] as? [String: Any],
           let content = messageObj["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
