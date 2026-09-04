# Changelog

All notable user-facing changes, feature additions, and improvements to OpenClip are documented here.

---

## v1.3.0 - 2026-09-04

### Highlights
- **`openclip.pasteboard` JavaScript Extension API**: Extensions can now read, inspect, and write clipboard content directly with granular type support and change-count tracking.
- **Customizable Popup Alignment & Vertical Positioning**: Configure popup bar alignment (Left, Center, Right) and vertical placement (Auto, Above cursor, Below cursor) in Preferences, with synchronized sub-action bar tracking ([#52](https://github.com/ganeshmshetty/openclip/pull/52)).
- **Full Multilingual Localization & Search**: Added complete UI translations for Traditional Chinese (`zh-Hant`), French (`fr`), and Japanese (`ja`), along with multi-lingual action search keyword indexing.
- **Storefront & Actions Tab Overhaul**: Redesigned extension storefront with category filter tabs and pagination, plus an NSOutlineView-based Actions preference hierarchy with zebra striping and drag-and-drop improvements.
- **Snooze & App Pause Rules**: Temporarily pause OpenClip from the status bar menu (15 min, 1 hour, etc.) or configure per-app pause toggles.

### Features & Improvements
- **Extension Runtime Script Budget & Interactive Cancellation**: Enforced a 60-second execution watchdog across process runners and added interactive task cancellation for long-running scripts.
- **Native AXWebArea Selection Cascade**: Accelerated selection detection across Chromium and WebKit browsers with direct AXWebArea integration and multi-app selection resilience.
- **Status Bar Menu Enhancements**: Added snooze presets, per-application pause toggles, and refined popup dismissal responsiveness.
- **Preferences UI Polish**: Added sectioned storefront views with filter tabs, rendered pagination triggers, and aligned group indicators.

### Fixes & Stability
- **Extension Security**: Prevented path traversal and unauthorized script execution in extension manifests ([#38](https://github.com/ganeshmshetty/openclip/issues/38)).
- **Clipboard & Pasteboard Preservation**: Preserved lazy pasteboard items and prevented clearing untouched clipboards ([#34](https://github.com/ganeshmshetty/openclip/issues/34)).
- **Delivery Context & Paste Races**: Guarded against application-switch paste races by snapshotting delivery context at trigger time ([#41](https://github.com/ganeshmshetty/openclip/issues/41)).
- **Secret Staging Race**: Eliminated file permission race conditions during secret storage staging with self-healing recovery ([#49](https://github.com/ganeshmshetty/openclip/issues/49)).
- **Update Flow & Sparkle Integration**: Improved release notes presentation in update prompts and preserved user settings across version updates.
- **Action Group Sheets & Drag-and-Drop**: Fixed group creation sheets and improved reordering in Preferences.

### Community
- Join our [Discord community](https://discord.gg/sy4MeFxf8) to share extensions, suggest features, and get support!

---

## v1.2.1 - 2026-09-02

### Features & Improvements
- **Context-Aware Web Search**: When triggered inside a supported web browser (Safari, Chrome, Arc, Brave, Edge, etc.), web searches now open directly in the active browser rather than defaulting to the system default browser ([#25](https://github.com/ganeshmshetty/openclip/issues/25)).
- **Configurable Bar Width Slider & Dynamic Packing**: Replaced fixed page sizes with an intuitive 5-level bar width slider and dynamic page packing in the floating popup HUD.
- **Command Line Flags**: Added CLI support for `--version` / `-v` and `--help` / `-h` flags for quick version and usage inspection from the terminal ([#29](https://github.com/ganeshmshetty/openclip/pull/29)).
- **Extension Local Icon Validation**: Added automated verification in `validate_extension.sh` to ensure referenced local icon files exist and are accessible ([#30](https://github.com/ganeshmshetty/openclip/pull/30)).

### Fixes & Stability
- **Action Group Persistence**: Preserved custom user action group configurations and member assignments across extension updates and catalog reloads ([#24](https://github.com/ganeshmshetty/openclip/issues/24)).
- **Toast Positioning**: Centered toast notifications in-place directly over the closed popup frame to prevent visual jumps during action execution.
- **Extension Update Error Reporting**: Enhanced extension updater to log and surface individual update failures instead of silently dropping errors ([#32](https://github.com/ganeshmshetty/openclip/pull/32)).
- **Calendar Event Cleanup**: Ensured temporary `.ics` event files are cleanly removed following Calendar imports with strict regular-file verification ([#31](https://github.com/ganeshmshetty/openclip/pull/31)).
- **Settings Type Safety**: Replaced unsafe force-casts in `SettingsStore.get` with safe fallback defaults ([#26](https://github.com/ganeshmshetty/openclip/pull/26)).
- **Documentation & Localization**: Synchronized documentation with Swift 6 and updated contributing prerequisites for Xcode 16+ ([#28](https://github.com/ganeshmshetty/openclip/pull/28)).

### Contributors
- @ayangweb ([#26](https://github.com/ganeshmshetty/openclip/pull/26), [#27](https://github.com/ganeshmshetty/openclip/pull/27), [#28](https://github.com/ganeshmshetty/openclip/pull/28), [#29](https://github.com/ganeshmshetty/openclip/pull/29), [#30](https://github.com/ganeshmshetty/openclip/pull/30), [#31](https://github.com/ganeshmshetty/openclip/pull/31), [#32](https://github.com/ganeshmshetty/openclip/pull/32))

---

## v1.2.0 - 2026-09-01

### Features & Improvements
- **Custom Action Groups & Sub-Action Bar**: Group multiple actions and extensions together into unified action items. Hovering reveals a floating horizontal sub-bar for instant sub-action selection, and clicking opens a scoped search palette.
- **Simplified Chinese Localization**: Full UI localization in Simplified Chinese (`zh-Hans`), adapting automatically to macOS system language preferences.
- **Search Engine Presets**: Added one-click engine presets (Google, DuckDuckGo, Kagi, Brave Search, Bing, Ecosia, and Custom) to the built-in Search action settings.
- **In-App Software Updates**: Integrated Sparkle 2 updater with automatic background update checks, status bar notifications, and release note presentation.
- **AI Loading Toast Lifecycle**: AI preset execution displays a non-blocking floating loading toast, smoothly transitioning to streaming result cards upon receipt.
- **Toast UI Scaling**: Result toasts and copy notifications scale dynamically with user-selected `popupScale` preferences.
- **Menu Bar Icon Visibility Toggle**: Added an option in General Preferences to hide the menu bar icon while keeping hotkey and selection triggers active.

### Fixes & Stability
- **Cursor Stickiness**: Resolved cursor stickiness across popup panel edges by installing AppKit tracking areas and asserting arrow cursors on interactive views.
- **Sub-Bar Coordinate Hit-Testing**: Fixed sub-bar hover state tracking using window coordinate conversions and dynamic click-through ignore handling.
- **AI Session State**: Preserved AI streaming session identifiers and active tasks across loading toast state transitions.
- **Empty Action Group Support**: Allowed creating and configuring empty action groups from Preferences without auto-disbandment.

### Contributors
- @ayangweb ([#5](https://github.com/ganeshmshetty/openclip/pull/5), [#12](https://github.com/ganeshmshetty/openclip/pull/12), [#13](https://github.com/ganeshmshetty/openclip/pull/13))
- @cauton2020 ([#3](https://github.com/ganeshmshetty/openclip/pull/3))

---

## v1.1.1 - 2026-08-28

### Features & Improvements
- **Launch Classification & Permission Recovery**: Added launch classifier distinguishing fresh installs, updates, and relaunches with a dedicated permission-recovery flow and UI when Accessibility access is missing.
- **Onboarding Redesign**: Rebuilt onboarding into a 4-step interactive wizard with curated recommended extensions, live sandbox preview, and resilient catalog resolution.
- **Reactive Extension Store**: Store install/remove now updates instantly with reactive state and immediate remove-button feedback.

### Fixes & Stability
- **Action Reordering**: Corrected reordering in the Actions preferences tab so drag order persists reliably.
- **Copied Feedback**: Default "Copied" toast now fires for any delivered copy (`.copy`/`.copyContent`/`.copyDefinition`) when no declared toast wins — previously only paste-context copies triggered it.
- **Brew Install Docs**: Simplified install docs to single-command `brew install --cask ganeshmshetty/tap/openclip`.

---

## v1.1.0 - 2026-08-26

### Features & Improvements
- **Anchored Action Configuration**: Replaced the edit sheet with an anchored popover accessed from the gear button or by double-clicking action rows, combining appearance and general settings into an inset-grouped editor with hero icon headers.
- **Unified Result Cards & Live Previews**: Standardized the result card presentation across all actions and AI tools with live preview support, consistent styling, and customization-resolved action icons.
- **Curated Onboarding & Recommendations**: Onboarding now recommends curated store extensions (including Quick Translate and Speak Selection) with full catalog resolution, deduplication, and resilient fallback icon rendering.
- **Extension Store Cache**: Introduced a shared TTL in-memory cache across the Store tab, Onboarding, and background update checks for faster catalog browsing.
- **App Rules & Menu Bar Polish**: Refined the App Rules tab with enhanced per-app configuration controls; pinned extension management to the top of the menu bar Extensions submenu.
- **Post-Onboarding Coach Marks**: Added contextual coach mark nudges to guide new users through Accessibility permissions and setup.

### Fixes & Stability
- **Selection & Cursor Classification**: Improved cursor detection to use system-wide cursor state (`NSCursor.currentSystem`), ensuring reliable text selection detection across all apps.
- **Gated Clipboard Fallback**: Gated clipboard fallback activation on text insertion cursors (I-beam) and successful paste probes.
- **Popup & Toast Interactions**: Clicks on the popup shadow ring now dismiss and fall through to background apps; toasts anchor cleanly to the popup frame with fixed shadow clipping.
- **Extension Catalog & Validator**: Updated catalog with bug fixes across 25 community extensions and aligned the manifest validator to accept payload-free service actions.

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