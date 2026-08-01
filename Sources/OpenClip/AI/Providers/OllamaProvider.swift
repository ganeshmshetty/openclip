import Foundation

@MainActor
public final class OllamaProvider: AIProvider {
    public var type: AIProviderType { .ollama }
    
    public let baseURL: String
    public let model: String
    
    public init(baseURL: String, model: String) {
        self.baseURL = baseURL.isEmpty ? "http://localhost:11434" : baseURL
        self.model = model.isEmpty ? "llama3" : model
    }
    
    public func process(prompt: String, text: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fullPrompt = "\(prompt): \(text)"
        let body: [String: Any] = [
            "model": model,
            "prompt": fullPrompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseText = json["response"] as? String {
            return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
