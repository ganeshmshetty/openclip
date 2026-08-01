# Design Specification: OpenClip AI Integration

**Date:** 2026-08-01  
**Status:** Approved / Draft  
**Target Module:** `Sources/OpenClip/AI/` & `Sources/OpenClip/UI/Preferences/` & `Sources/OpenClip/UI/Popup/`

---

## 1. Overview

OpenClip AI Integration brings instant, on-device and cloud-powered AI features directly into the text selection popup bar without cluttering the interface. It introduces a dedicated **AI Preferences Tab**, a **Single `✨ AI` Button** on the main popup bar that seamlessly transitions into an **AI Sub-Bar** (inspired by completion mode), and modular support for **Apple Intelligence**, **Ollama Local LLMs**, **Cloud APIs (OpenAI/Claude/Gemini)**, and **Browser Redirection (ChatGPT/Claude web)**.

---

## 2. User Experience & Popup Bar UX

### 2.1 The 3-Mode Bar Transition
The `PopupView` bar supports three fluid modes:
1. **Normal Actions Mode:** `[ ✂️ Cut | 📋 Copy | 📄 Paste | 🔤 Transform | ✨ AI ]`
2. **Completion Mode (Existing):** `[ ⌄ | word1 | word2 | word3 ]`
3. **AI Sub-Bar Mode (New):** `[ ⌃ | ✨ Fix | 📝 Summarize | 🌐 Translate | 💡 Explain | 💬 Prompt... ]`

### 2.2 Execution Flow
- Clicking **`✨ AI`** on the main popup bar smoothly transitions the bar into **AI Sub-Bar Mode**.
- Clicking **`⌃`** (Chevron Left/Up) returns to the Normal Actions Mode.
- Clicking an AI Sub-Action (`Fix`, `Summarize`, `Translate`, `Explain`, `Prompt`):
  - **Ollama / Cloud API:** Streams response live into an expandable **Inline Result Card** positioned directly below/above the bar, equipped with **`📋 Copy`**, **`⚡️ Replace`**, and **`🔄 Retry`** buttons.
  - **Apple Intelligence:** Triggers system `Writing Tools` / native on-device summarizer.
  - **Browser Redirection:** Opens `https://chatgpt.com/?q={text}` or `https://claude.ai` in the default browser.

---

## 3. Architecture & Key Components

```
Sources/OpenClip/
├── AI/
│   ├── AIServiceManager.swift       # Singleton orchestrator for active AI provider
│   ├── AIProvider.swift             # Protocol defining AI execution API
│   ├── Providers/
│   │   ├── AppleIntelligenceProvider.swift # Native Apple Writing Tools & Foundation Models
│   │   ├── OllamaProvider.swift            # Local LLM API (http://localhost:11434)
│   │   ├── CloudAPIProvider.swift          # OpenAI / Claude / Gemini streaming API
│   │   └── BrowserRedirectProvider.swift   # Web URL scheme redirection
├── UI/
│   ├── AI/
│   │   └── AIResultOverlayView.swift  # Floating glass streaming result card
│   ├── Preferences/
│   │   └── AITab.swift               # Dedicated AI settings tab in PreferencesView
```

---

## 4. Preferences: Dedicated "AI" Tab

In `PreferencesView.swift`, a new **`AI`** tab (`brain` / `sparkles` icon) is added to the sidebar.

### Settings Options:
1. **Active Provider Selector (Single Choice):**
   - `Apple Intelligence (On-Device)` (Default on macOS Sequoia / Apple Silicon)
   - `Ollama (Local LLM)`
   - `Cloud API (OpenAI / Claude / Gemini)`
   - `Browser Redirection`
2. **Cloud API Configuration:**
   - API Key input (Securely stored in Keychain or AppStorage)
   - Model selection (`gpt-4o-mini`, `claude-3-5-sonnet`, `gemini-1.5-flash`)
3. **Ollama Configuration:**
   - Server URL (default: `http://localhost:11434`)
   - Model selection (`llama3`, `mistral`, `qwen2.5`, `deepseek-coder`)
4. **Browser Redirection Configuration:**
   - Preferred AI site (`ChatGPT`, `Claude`, `Perplexity`, or `Custom URL`)

---

## 5. Security & Privacy
- **Zero Data Leakage:** On-device providers (Apple Intelligence & Ollama) never send selected text outside the device.
- **Keychain Storage:** Cloud API keys are stored encrypted.

---

## 6. Verification & Test Plan
1. **Unit Tests:** `AITabTests.swift` and `AIServiceManagerTests.swift` verifying provider resolution, prompt formatting, and state persistence.
2. **Runtime Verification:** Verify live popup bar transition into AI Sub-Bar Mode using `./scripts/dev_run.sh`.
