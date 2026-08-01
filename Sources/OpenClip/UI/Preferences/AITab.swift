import SwiftUI

@MainActor
public struct AITab: View {
    @ObservedObject private var aiManager = AIServiceManager.shared
    
    public init() {}
    
    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $aiManager.isAIEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Features")
                            .font(.headline)
                        Text("Show AI tools in the text selection popup bar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active AI Engine")
                        .font(.headline)
                    Text("Select which provider powers AI features when invoked.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
                
                Picker("", selection: $aiManager.activeProviderRaw) {
                    Text("Apple").tag(AIProviderType.apple.rawValue)
                    Text("Ollama").tag(AIProviderType.ollama.rawValue)
                    Text("Cloud API").tag(AIProviderType.cloud.rawValue)
                    Text("Browser").tag(AIProviderType.browser.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(!aiManager.isAIEnabled)
            
            Section(header: Text("Provider Settings")) {
                if aiManager.activeProviderType == .apple {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Apple Intelligence (On-Device)", systemImage: "applelogo")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Uses native macOS Writing Tools & on-device models. Zero API key needed, 100% private.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .cloud {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI / Claude API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("sk-...", text: $aiManager.cloudAPIKey)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Model", selection: $aiManager.cloudModel) {
                            Text("gpt-4o-mini").tag("gpt-4o-mini")
                            Text("gpt-4o").tag("gpt-4o")
                            Text("claude-3-5-sonnet").tag("claude-3-5-sonnet")
                            Text("gemini-1.5-flash").tag("gemini-1.5-flash")
                        }
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .ollama {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ollama Server Endpoint")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("http://localhost:11434", text: $aiManager.ollamaURL)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Model Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("llama3", text: $aiManager.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                } else if aiManager.activeProviderType == .browser {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Default Chatbot", selection: $aiManager.browserPreset) {
                            Text("ChatGPT (OpenAI)").tag("chatgpt")
                            Text("Claude (Anthropic)").tag("claude")
                            Text("Perplexity AI").tag("perplexity")
                            Text("Google Gemini").tag("gemini")
                            Text("DeepSeek").tag("deepseek")
                            Text("Custom URL...").tag("custom")
                        }
                        
                        if aiManager.browserPreset == "custom" {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Web URL")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                TextField("https://custom-ai.com/?q={text}", text: $aiManager.browserURLTemplate)
                                    .textFieldStyle(.roundedBorder)
                                Text("Use **{text}** as a placeholder for the prompt and selection.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .disabled(!aiManager.isAIEnabled)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(12)
    }
}
