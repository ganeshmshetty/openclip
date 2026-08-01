# App Rules UX Design Specification

## Problem & Goals
Currently, the App Rules interface only allows selecting from currently running applications and uses inline collapsible rows for tweaking rules. Users need:
1. The ability to select installed applications from `/Applications` (even if not running) as well as enter custom bundle IDs or wildcard patterns (e.g. `com.jetbrains.*`).
2. A simplified primary view focusing on blacklisting (disabling OpenClip per app).
3. Advanced rule controls accessible via a clean three-dots (`...`) dropdown menu per app.

## Components & Architecture

### 1. App Picker Modal (`AppPickerSheet.swift`)
The new picker sheet features three tabs:
- **Running Apps**: Lists active processes with their bundle IDs and icons.
- **Installed Apps**: Asynchronously scans `/Applications` and `~/Applications` for installed `.app` bundles, reading their `Info.plist` display name, bundle identifier, and application icon.
- **Custom / Wildcard**: A text entry field allowing manual input of bundle IDs or wildcards (e.g. `com.apple.Terminal`, `com.jetbrains.*`).

### 2. App Rules List (`AppRulesTab.swift`)
Redesigned `AppRulesTab` displaying an inset list of configured rules:
- **App Row**:
  - Left: App Icon (or fallback icon for wildcards/uninstalled apps) + App Name + Bundle Identifier text.
  - Middle: Status badge indicating mode (`[Disabled]`, `[No Formatting]`, `[Clipboard Mode]`, `[Active]`).
  - Right: Quick **Enable/Disable Toggle** + **Three-Dots (`...`) Menu Button**.

### 3. Three-Dots Action Menu (`NSMenu` / `Menu`)
Options available in the `...` menu for each rule:
- 🔴 **Disable OpenClip** / 🟢 **Enable OpenClip**
- 🧼 **Toggle Text Formatting** (disables formatting actions for code editors)
- ⚡️ **Toggle Clipboard Mode** (forces Cmd+C for non-AX/Webview apps)
- 🗑️ **Delete Rule**

## Data Model & Persistence
- Conforms to existing `AppRule` schema in `Sources/Core/Rules/AppRule.swift`.
- Rule updates write directly to `RuleEngine.shared.addOrUpdateRule(...)` and persist to `~/.openclip/rules.json`.

## Verification Strategy
- **Unit Tests**: Add tests verifying installed app scanning helper logic and `RuleEngine` state updates.
- **Manual Verification**: Run `xcodebuild test` and launch via `./scripts/dev_run.sh` to test adding installed apps and toggling rules via the three-dots menu.
