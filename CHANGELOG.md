# Changelog

All notable user-facing changes, feature additions, and improvements to OpenClip are documented here.

---

## v1.0.1 - 2026-08-22

### Features & Improvements
- **Rich Content & Formatted Text**: OpenClip captures and pastes rich text formatted with HTML and RTF, preserving text styles, headings, and links across supported applications.
- **Mouse-Hold Trigger**: Added a configurable mouse-hold timer in General Preferences, allowing you to summon OpenClip simply by holding down the mouse click without dragging.
- **Expanded Calendar Providers**: Added support for additional calendar services in event creation extensions.
- **Normalized Popup Sizing**: Rebalanced proportions and typography across all 5 visual scale levels for crisp rendering on both Retina and standard displays.

### Fixes & Stability
- **Extension Trust Handling**: Fixed an issue where locally modified extensions could trigger unexpected trust warnings during editing.
- **Browser Selection Reliability**: Resolved edge cases in Safari and Chromium-based browsers to ensure selections are captured instantly without lag.

---

## v1.0.0 - 2026-08-21

The initial major release of OpenClip — the fast, native floating action bar for macOS that turns selected text into instant actions.

### Floating Action Bar
- **Instant Contextual Trigger**: Select text in any macOS application, and a floating action bar appears right next to your cursor with relevant actions ready to use.
- **Adaptive Positioning**: Anchors to where you release the mouse, automatically positioning itself above or below to avoid covering the text you are reading.
- **Three Themes**: Choose between **Glass** (macOS Liquid Glass frosted blur), **Dark** (OLED black contrast), or **Light** (clean white), fully matching your system appearance.
- **Instant Hover Feedback**: Seamless buttons with smooth hover animations and pagination for longer action lists.
- **Clipboard Fallback**: When activated without an active text selection, OpenClip intelligently works with your current clipboard contents.

### Built-in Productivity Actions
- **Smart Web Search**: Instantly search Google, DuckDuckGo, Wikipedia, or your preferred search engine, automatically formatted and encoded.
- **Inline Calculator**: Highlight mathematical equations (e.g. `45 * 12 + 8%`) to calculate answers inline.
- **Dictionary & Definitions**: Look up instant word definitions powered by macOS system dictionaries without opening another app.
- **Word Completion & Spelling**: Automatic word completion and spelling suggestions for incomplete words.
- **Text Transformations**: One-click formatting tools including **UPPERCASE**, **lowercase**, **Title Case**, **camelCase**, **JSON Pretty Print**, and **Trim Whitespace**.
- **macOS Services & Sharing**: Directly access system Share extensions and Services menu items for selected text.

### Action Search Palette
- **Global Search Shortcut (Option+Command+C)**: Open a quick search palette over your entire action library using a customizable hotkey.
- **Recent Action Ranking**: Quickly find actions with keyboard navigation, ranked by your recent usage.

### AI Assistants & Streaming Results
- **Multiple AI Providers**: Connect OpenClip to Apple Intelligence, local Ollama models, OpenAI (ChatGPT), or Anthropic (Claude).
- **Streaming Live Previews**: Watch AI responses stream in real time inside native result cards.
- **One-Click Insert & Replace**: Paste generated AI results directly over your selected text, copy to clipboard, or expand in the preview card.

### Extensions & Custom Actions
- **In-App Extension Store**: Browse, search, install, and update community extensions with a single click.
- **Universal Custom Action Builder**: Create custom web searches, text snippets, and scripts without writing code.
- **9,000+ Icon Library**: Customize actions using native SF Symbols or search popular icon collections including Lucide, Font Awesome, and Material Symbols.
- **Supported Runtimes**: Extensions support JavaScript, AppleScript, Shell scripts, URL templates, and macOS Shortcuts.

### App Rules & Customization
- **Action Reordering**: Rearrange actions in Preferences to build your ideal workflow.
- **Per-App Rules**: Configure OpenClip to behave differently in specific apps — enable auto-paste, restrict to hotkey-only, or disable completely in games and full-screen tools.
- **Preferences Interface**: Clean settings interface organized into General, Actions, App Rules, AI Services, and Extensions tabs.

### Privacy & Performance
- **100% Local & Private**: No analytics, no tracking, and no external telemetry.
- **Direct Accessibility Integration**: Reads selected text directly via macOS Accessibility APIs with zero background battery drain.
- **Secure Keychain Storage**: API keys and credentials are encrypted securely in the macOS Keychain.
- **Subprocess Safety**: Scripts run in isolated process groups with automated timeouts to prevent hanging.
- **Start at Login**: Built-in macOS Login Items integration for seamless system startup.