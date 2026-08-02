# Preferences & Customization

OpenClip offers extensive customization for action ordering, display labels, custom icons, and AI provider integration through the Preferences window.

---

## Opening Preferences

You can open OpenClip Preferences in two ways:
- Click the OpenClip menu bar icon and select **Preferences...**
- Press `Cmd + ,` while the OpenClip popup bar or settings window is focused.

---

## Action Catalog & Drag-and-Drop Reordering

The **Actions** tab lists all available builtin actions, user-configured custom actions, and installed extension packages.

```
Preferences > Actions
├── Drag handle (≡) to reorder actions in the floating popup bar
├── Toggle checkbox to enable or disable individual actions
└── Click 'Edit' () to customize title and icon overrides
```

### How Action Ordering Works
- Dragging actions changes their relative order in the floating popup bar.
- Action ordering is saved automatically via [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift) under key `actionOrder`.

---

## Customizing Action Titles & Icons

OpenClip allows overriding the display title and icon for any action without editing code or manifests.

### Display Overrides via `ActionCustomizationManager`
- **Custom Title**: Override the default name displayed in popup tooltips or preferences tables.
- **Custom SF Symbol**: Enter any valid macOS SF Symbol name (e.g. `sparkles`, `doc.on.doc`, `terminal`).
- **Custom Text Icon**: Display a 1–2 character text icon instead of a symbol.

All overrides are managed via [`ActionCustomizationManager`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionCustomizationManager.swift) and stored persistently in `SettingsStore`.

---

## AI Provider Setup

OpenClip includes an AI assistant overlay that processes text selections using local or cloud AI models.

Navigate to **Preferences > AI Assistant** to configure your provider:

| Provider | Description | Setup Requirements |
| :--- | :--- | :--- |
| **Apple Intelligence** | On-device macOS intelligence framework | macOS 15.0+ with Apple Intelligence enabled |
| **Ollama (Local)** | Privacy-focused local LLM execution | Running Ollama instance (`http://localhost:11434`) |
| **Cloud AI (OpenAI / Claude)** | Cloud API language models | Valid API Key stored securely in Keychain |
| **Browser Redirect** | Opens AI query in browser | No API key required |

### AI Settings Channel
AI settings are managed through `AIServiceManager` and isolated to ensure security and privacy.
