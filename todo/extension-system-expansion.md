# OpenClip Extension System Expansion

| Field | Value |
| :--- | :--- |
| **Title** | OpenClip Extension System Expansion |
| **Author** | (implementation team) |
| **Date** | 2026-08-03 |
| **Status** | Draft |
| **Repo** | `/Users/ganesh/dev/openclip` |
| **Audience** | Senior engineers implementing against Core + App targets |

---

## Overview

OpenClip’s extension surface today can load packages from `~/.openclip/extensions`, parse JSON manifests / snippet headers, and materialize four runtimes (URL template, shell script file, AppleScript, JavaScript). That path is real and tested (`ExtensionManager`, `DefaultActionFactory`, `GoldenExtensionPlatformTests`), but it is intentionally thin: one visibility rule (regex on URL actions only), package-level options only, option values read through raw `UserDefaults` / `@AppStorage`, a minimal JS bridge (`openUrl` / `pasteText` / `showNotification`), and an `ActionResult` enum that can only drive pasteboard / URL / Services side-effects — never structured UI, stay-visible behavior, settings prompts, key presses, or Shortcuts.

This design expands **OpenClip’s own** extension system so third-party authors can ship rich extensions without forking the app. The model is hybrid:

1. **Declarative fast path** — JSON manifest fields declare action kinds, visibility, after-behavior, and options; the factory materializes pure Core or thin App actions.
2. **Live JavaScript surface** — the only in-process runtime that can call back into OpenClip (structured results, options, settings-required, stay-visible). Shell and AppleScript remain one-shot scripts with an expanded stdout/result protocol; they do **not** get a live host API.

Presentation stays **capability, not canvas**: extensions compose `BubbleContent` / status / menu building blocks and choose presets; the app owns all pixels, fonts, materials, and chrome via design tokens (`BubbleCardView`, popup bar, preferences sheets).

---

## Background & Motivation

### Current architecture (verified in code)

```mermaid
flowchart LR
  Disk["~/.openclip/extensions"] --> EM["ExtensionManager"]
  EM -->|"onRegister / onUnregister"| AC["ActionCoordinator"]
  AC --> AR["ActionRegistry"]
  EM --> Factory["ActionFactory<br/>(DefaultActionFactory)"]
  Factory --> Actions["URLTemplateAction / ScriptAction<br/>JavaScriptAction / AppleScriptAction"]
  Popup["PopupWindowController"] --> AC
  Popup --> Perform["action.perform(context)"]
  Perform --> ARS["ActionResult"]
  ARS --> Handler["DefaultActionResultHandler"]
  ARS --> Hide["popup.hide() always"]
```

| Seam | File | Role today |
| :--- | :--- | :--- |
| Action protocol | `Sources/Core/Actions/Action.swift` | `id/title/icon/chrome/isEnabled/perform/actionOptions` |
| Registry | `Sources/Core/Actions/ActionRegistry.swift` | Catalog + disable filter + order |
| Coordinator | `Sources/Core/Actions/ActionCoordinator.swift` | Wires manager callbacks → registry; resolves app rules |
| Result | `Sources/Core/Actions/ActionResult.swift` | `success/failure/simulatePaste/openURL/copy/cut/paste/showServices/none` |
| Bubble model | `Sources/Core/Actions/BubbleContent.swift` | Pure value types: rows, footer, emphasis (info/result/menu) |
| Options model | `Sources/Core/Actions/ExtensionOption.swift` | `string/boolean/multiple/secret` |
| Manifest | `Sources/Core/Extensions/Manifest/*`, `ExtensionManager.ExtensionMetadata` | Multi-action array already decoded; options package-level |
| Factory | `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift` | Birth door for App runtimes |
| JS runtime | `Sources/OpenClip/Actions/JavaScriptAction.swift` | JSC + raw UserDefaults options |
| Effects | `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift` | Pasteboard / URL / Services / key paste |
| Popup | `Sources/OpenClip/UI/Popup/PopupWindowController.swift` | Always `hide()` after `onResult` |
| Settings UI | `DynamicActionConfigView.swift` | `@AppStorage("action.<id>.option.<opt>")` |
| Secrets | `KeychainStore.swift` + `AIServiceManager` | Pattern exists; **not** used for extension secrets |

### Pain points

1. **Options leak past SettingsStore.** `JavaScriptAction` lines 66–67 use `UserDefaults.standard`; `DynamicActionConfigView` uses `@AppStorage` with the same key shape. AGENTS.md forbids new direct `UserDefaults.standard` call sites; secrets must not live in plists.
2. **Visibility is incomplete.** Only `URLTemplateAction.isEnabled` honors `regex`. `ScriptAction` / `JavaScriptAction` / `AppleScriptAction` only require non-empty selection. No app-bundle filters, no negation, no capture groups passed into perform.
3. **`ActionResult` cannot reach UI.** Calculate/AI already build `BubbleContent` in App/Core, but extensions cannot return a result card, status tick, stay-visible, or “open my settings.” Popup always dismisses on result (`PopupWindowController` `onResult` → `hide()`).
4. **JS host is too small.** Bridge exposes `input.text`, `options`, `openUrl`, `pasteText`, `showNotification` (deprecated `NSUserNotification`). No matched text, no bubble, no configuration signal, no key press / Shortcut.
5. **Manifest kinds are underused.** `ExtensionActionKind` already names `url/js/applescript/shellInline/scriptFile`, but factory routing mixes `metadata.url`, `scriptCode` + type string, and file extension. No key-press, Service name, or Shortcuts kinds.
6. **Multi-action support is partial.** `ExtensionManager.loadManifestExtension` already enumerates `manifest.actions`, but:
   - ID generation in the factory is fragile (`identifier.action.<title>`);
   - options are only package-level and applied to every action;
   - uninstall matches by package prefix (good) but reload semantics need care when one action of many is toggled.
7. **`ExtensionOptionMetadata` drops picker choices.** Domain `ExtensionOption.options: [String]?` exists; metadata decode does not carry `options` / choices, so factory never wires `.multiple` choices.

---

## Goals & Non-Goals

### Goals

1. Hybrid author model: declarative JSON + live JS host; shell/AppleScript stay one-shot.
2. Multiple action kinds: URL, shell, AppleScript, JavaScript, key press, macOS Service, Shortcut.
3. Declarative visibility: requirements, regex (± negation), source-app bundle IDs (± negation); matched text + captures available to runtimes.
4. Result / behavior pipeline: copy/paste/replace outcomes, stay-visible / pin, multi-action packages, per-action config.
5. Options: primitive types + secrets in Keychain, generated settings UI, runtime read, “settings required” signal that opens the right sheet **without** presentation `switch action.id`.
6. Preserve module boundaries and AGENTS.md hard rules.
7. Phased, independently verifiable delivery (build + tests green each phase).

### Non-Goals

- Sandboxing, capability tokens, code signing, marketplace.
- TypeScript tooling / npm toolchain.
- Free-form custom rendering (embedded WKWebView, arbitrary fonts/colors).
- Full icon-rendering modifier engine.
- In-app visual manifest editor / extension builder UI.
- Importing foreign product extension formats as a product goal (legacy key aliases already in decoder may remain for compatibility only).

---

## Key Decisions

| # | Decision | Rationale |
| :--- | :--- | :--- |
| K1 | **Keep `Action` + `ActionResult` as the execution spine; expand additively** | Every builtin and extension already returns `ActionResult`. A parallel outcome type would fork `PopupView.onResult`, `BubbleOutcome`, and tests. Additive enum cases + a small dismiss-policy helper minimize blast radius. |
| K2 | **JS is the only live host; shell/AppleScript stay one-shot** | In-process JSC already exists. Giving shell a bidirectional RPC would require a daemon protocol and timeouts far beyond current `Constants.scriptTimeout`. Expand shell JSON stdout instead. |
| K3 | **Structured presentation via `BubbleContent` + thin new result cases** | `BubbleContent` / `BubbleCardView` already power AI, Calculate, transform menus. Extensions compose the same blocks; app renders. No second card model. |
| K4 | **`keepVisible(ActionResult)` wrapper for stay/pin** | Avoids a free-floating flag on every case. Popup inspects top-level result: unwrapped effect runs through `ActionResultHandler`; dismiss is skipped. Nested results can still be `.copy` / `.showBubble` / etc. |
| K5 | **`openConfiguration(ConfigurationRequest)` carries actionID as data, not UI switch** | Presentation looks up `Action` from registry by id and presents `EditActionSheet` / dynamic options. No `switch action.id` in popup/preferences. |
| K6 | **Option keys stay `action.<actionID>.option.<identifier>` but only via `SettingKey` + `SettingsStore`** | Preserves values users already have; eliminates direct UserDefaults call sites. Secrets route to `KeychainStore` with the same account string, never written to UserDefaults. |
| K7 | **Visibility evaluated in Core via `ActionVisibility` shared by all extension actions** | One pure evaluator; factory attaches rules to each action. Builtin actions unchanged. Matched spans live on `ActionContext` (or a side bag on a new `ExtensionExecutionContext`) so perform() does not re-run regex. |
| K8 | **New kinds are first-class `ExtensionActionKind` cases + thin App/Core action types** | Key press / Shortcut need AppKit / `NSWorkspace` — App target. Service reuses `.showServices` or named service invocation in the handler. |
| K9 | **Per-action options override package options by identifier** | Multi-action packages need distinct API keys without duplicating whole option blocks. Merge: package defaults ← action overrides. |
| K10 | **No sandbox; authors are trusted** | Matches current install model (`installExtension` copies into `~/.openclip/extensions`). Document trust boundary; do not pretend isolation. |
| K11 | **Factory remains the Birth Door; manager never touches `ActionRegistry.shared`** | Existing `onRegister`/`onUnregister` wiring in `ActionCoordinator.loadInitialState()` stays the only registry path. |
| K12 | **Subprocess watchdog remains mandatory** | Any new shell/Shortcut-adjacent process uses `TimeoutFlag` + `Constants.scriptTimeout` (30s) pattern from `ScriptAction` / `CustomAction`. |

---

## Proposed Design

### 1. End-state architecture

```mermaid
flowchart TB
  subgraph Authors
    Manifest["openclip.json<br/>actions[] + options[] + requirements"]
    JSFile["*.js with openclip.* host"]
    Shell["*.sh / AppleScript one-shot"]
  end

  subgraph Core
    EM["ExtensionManager"]
    Vis["ActionVisibility.evaluate"]
    OptKey["SettingKey.actionOption"]
    AR["ActionRegistry"]
    AC["ActionCoordinator"]
    Ctx["ActionContext + MatchInfo"]
    Res["ActionResult + BubbleContent"]
  end

  subgraph App
    Factory["DefaultActionFactory"]
    JS["JavaScriptAction + OpenClipJSHost"]
    Handler["DefaultActionResultHandler"]
    Popup["PopupWindowController"]
    Prefs["DynamicActionConfigView + Keychain"]
  end

  Manifest --> EM
  JSFile --> Factory
  Shell --> Factory
  EM --> Factory
  Factory --> EM
  EM -->|onRegister| AC --> AR
  Popup --> AC
  Popup --> Ctx
  Ctx --> Vis
  Vis --> AR
  Popup --> JS
  JS --> OptKey
  JS --> Res
  Res --> Handler
  Res --> Popup
  Prefs --> OptKey
  Prefs --> KeychainStore
```

### 2. Manifest shape (v2, backward compatible)

Existing keys continue to decode (`identifier`/`Identifier`, singular `action`, etc.). New fields are optional.

```json
{
  "identifier": "com.example.translator",
  "name": "Translator",
  "version": "2.0.0",
  "options": [
    {
      "identifier": "apiKey",
      "label": "API Key",
      "type": "secret"
    },
    {
      "identifier": "targetLang",
      "label": "Target language",
      "type": "multiple",
      "default": "es",
      "values": ["en", "es", "fr", "de"]
    }
  ],
  "actions": [
    {
      "id": "translate",
      "title": "Translate",
      "icon": "symbol(globe)",
      "type": "js",
      "script": "translate.js",
      "requirements": {
        "regex": "\\S+",
        "apps": ["com.apple.TextEdit", "com.microsoft.Word"],
        "appsMode": "allow",
        "requiresSelection": true,
        "requiredOptions": ["apiKey"]
      },
      "after": "show-result",
      "stayVisible": false,
      "options": [
        {
          "identifier": "formal",
          "label": "Formal tone",
          "type": "boolean",
          "default": "false"
        }
      ]
    },
    {
      "id": "open-docs",
      "title": "Docs",
      "type": "url",
      "url": "https://example.com/docs?q={text}"
    },
    {
      "id": "paste-upper",
      "title": "Uppercase",
      "type": "shell",
      "script": "upper.sh",
      "after": "paste-result"
    },
    {
      "id": "run-shortcut",
      "title": "Run Shortcut",
      "type": "shortcut",
      "shortcutName": "Process Selection"
    },
    {
      "id": "bold-key",
      "title": "Bold",
      "type": "keypress",
      "keyPress": { "key": "b", "modifiers": ["command"] },
      "requirements": { "apps": ["com.apple.iWork.Pages"], "appsMode": "allow" }
    }
  ]
}
```

#### Core types (new / extended)

```swift
// Sources/Core/Extensions/Manifest/ActionRequirements.swift
public struct ActionRequirements: Codable, Sendable, Equatable {
    /// If non-nil, selection must match (or not match if `regexNegated`).
    public var regex: String?
    public var regexNegated: Bool
    /// Bundle IDs to allow or deny.
    public var apps: [String]?
    public var appsMode: AppsMode  // .allow / .deny
    public var requiresSelection: Bool
    /// Option identifiers that must be non-empty before the action is usable.
    /// Empty required secrets → action can still appear but perform returns `.openConfiguration`.
    public var requiredOptions: [String]?

    public enum AppsMode: String, Codable, Sendable {
        case allow
        case deny
    }
}

public enum ActionAfterBehavior: String, Codable, Sendable {
    case copyResult = "copy-result"
    case pasteResult = "paste-result"
    case showResult = "show-result"   // wrap string outcome in BubbleContent
    case none = "none"
    /// Honor runtime-returned ActionResult only (default for JS).
    case `default` = "default"
}

// Extend ExtensionActionMetadata:
//   requirements, after, stayVisible, shortcutName, keyPress, serviceName,
//   options: [ExtensionOptionMetadata]?, captureGroups: Bool?
```

```swift
// Sources/Core/Extensions/Manifest/ExtensionActionKind.swift — extend
public enum ExtensionActionKind: String, Codable, Sendable, Equatable {
    case url
    case js
    case applescript
    case shellInline
    case scriptFile
    case keyPress      // new
    case service       // new — named or generic Services picker
    case shortcut      // new — Shortcuts app by name
}
```

**ID rule (stabilize multi-action):**

```text
actionID = metadata.id
        ?? "\(manifest.identifier).action.\(index)"   // stable by index, not title
// If metadata.id is a bare slug ("translate"), factory expands to
// "\(manifest.identifier).\(slug)" to keep global uniqueness.
```

`ExtensionManager.uninstallExtension` already matches `actionID.hasPrefix(meta.identifier + ".")` or equality — keep that.

### 3. Visibility & match info

```swift
// Sources/Core/Actions/ActionMatchInfo.swift
public struct ActionMatchInfo: Sendable, Equatable {
    /// Full selection text.
    public let text: String
    /// Substring matched by requirements.regex (full match); equals `text` if no regex.
    public let matchedText: String
    /// Regex capture groups 1...n (group 0 excluded).
    public let captures: [String]
    public let sourceBundleID: String?
}

// Extend ActionContext:
public struct ActionContext: Sendable {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    /// Populated by the popup/coordinator when resolving enabled actions for a specific action.
    /// Nil for builtins that don't use it.
    public let match: ActionMatchInfo?

    public init(selection: SelectionContext,
                modifiers: ModifierFlags = [],
                match: ActionMatchInfo? = nil) { ... }
}
```

```swift
// Sources/Core/Actions/ActionVisibility.swift
public enum ActionVisibility {
    /// Pure function — no UserDefaults, no AppKit.
    public static func isEnabled(
        requirements: ActionRequirements?,
        legacyRegex: String?,
        context: ActionContext
    ) -> (enabled: Bool, match: ActionMatchInfo)

    /// True when requiredOptions are missing values (caller supplies resolved option map).
    public static func missingRequiredOptions(
        requirements: ActionRequirements?,
        resolvedOptions: [String: String]
    ) -> [String]
}
```

**Evaluation order:**

1. `requiresSelection` (default `true` for extension actions) → empty text disables (except actions that set `requiresSelection: false`, e.g. pure Shortcut).
2. App allow/deny list vs `context.selection.sourceApp.bundleIdentifier`.
3. Regex match / negated match; on success build `ActionMatchInfo`.
4. `ActionRegistry.availableActions` still applies disabled IDs + formatting policy; per-action `isEnabled` calls the shared evaluator.

**Factory attachment pattern** — introduce a small Core wrapper or store rules on each extension action type:

```swift
public struct ExtensionActionRules: Sendable {
    public let requirements: ActionRequirements?
    public let legacyRegex: String?
    public let after: ActionAfterBehavior
    public let stayVisible: Bool
}
```

Each extension action (`URLTemplateAction`, `ScriptAction`, `JavaScriptAction`, …) gains optional `rules: ExtensionActionRules` and implements:

```swift
public func isEnabled(for context: ActionContext) -> Bool {
    ActionVisibility.isEnabled(requirements: rules.requirements,
                               legacyRegex: rules.legacyRegex ?? regexPattern,
                               context: context).enabled
}
```

**Match plumbing (important):** `isEnabled` and `perform` both need the same match. Options:

- **A (chosen):** Popup/coordinator, when invoking `perform`, re-runs `ActionVisibility` for that action and passes `ActionContext(selection:modifiers:match:)`. Cheap (one regex).
- **B:** Cache match on a side table keyed by action id — more state, easy to stale.

Choose **A**. Update `PopupView` action invocation site to build matched context before `perform`.

### 4. ActionResult expansion (additive)

```swift
// Sources/Core/Actions/ActionResult.swift
public enum ActionResult: Sendable {
    // --- existing ---
    case success
    case failure(Error)
    case simulatePaste
    case openURL(URL)
    case copy(String)
    case cut(String)
    case paste(String)
    case showServices(String)
    case none

    // --- new (additive) ---

    /// Show a structured bubble; popup stays up until user acts or dismisses.
    case showBubble(BubbleContent)

    /// Lightweight non-modal status (checkmark / error) rendered by app chrome.
    case showStatus(StatusFeedback)

    /// Open configuration UI for an action (settings-required / not signed in).
    case openConfiguration(ConfigurationRequest)

    /// Simulate an arbitrary key chord in the frontmost app.
    case keyPress(KeyPressSpec)

    /// Run a Shortcuts app shortcut by name, passing selection as input when possible.
    case runShortcut(name: String, input: String?)

    /// Run handler effect(s) but do not dismiss the popup bar.
    /// Example: `.keepVisible(.copy(text))` or `.keepVisible(.showStatus(...))`.
    case keepVisible(ActionResult)

    /// Sequential effects; dismiss policy derived from the last element's policy
    /// unless any element is `.keepVisible` / `.showBubble` / `.openConfiguration`.
    case sequence([ActionResult])
}

public struct StatusFeedback: Sendable, Equatable {
    public enum Style: String, Sendable { case success, error, info }
    public var message: String
    public var style: Style
    public var symbolName: String?  // optional SF Symbol preset name; app maps to token
}

public struct ConfigurationRequest: Sendable, Equatable {
    public var actionID: String
    public var reason: String?
    public var missingOptionIDs: [String]
}

public struct KeyPressSpec: Sendable, Equatable {
    public var key: String          // "b", "return", "escape", or virtual key name
    public var modifiers: [KeyModifier]  // command/shift/option/control
    public enum KeyModifier: String, Codable, Sendable {
        case command, shift, option, control
    }
}
```

**Dismiss policy (derived, not a parallel API):**

```swift
extension ActionResult {
    /// Whether PopupWindowController should call hide() after handling.
    public var dismissesPopup: Bool {
        switch self {
        case .keepVisible, .showBubble, .showStatus, .openConfiguration, .none, .success:
            return false
        case .sequence(let items):
            // Dismiss only if every item would dismiss (empty → false).
            return !items.isEmpty && items.allSatisfy(\.dismissesPopup)
        case .failure:
            return false
        default:
            return true  // paste/copy/cut/openURL/showServices/keyPress/runShortcut/simulatePaste
        }
    }

    /// Side-effect payload to send to ActionResultHandler (unwrap keepVisible).
    public var effectForHandler: ActionResult? { ... }
}
```

**Note on copy vs stay:** Today copy dismisses. Authors who want “copy and keep bar” return `.keepVisible(.copy(text))`. Declarative `stayVisible: true` in manifest is applied by the factory’s result adapter (see §6).

**BubbleContent leverage** — extend only where needed:

```swift
// Optional additive on BubbleContent (non-breaking defaults):
public var pinToBar: Bool  // default false; if true, bubbleBlocksDismiss + bar stays
```

Footer options already use `BubbleOutcome.perform(ActionResult)` — new result cases flow through the same path once `handleResult` understands them. Implement reserved `BubbleOutcome.showSubMenu` only if a phase needs nested menus; until then JS can return `.showBubble` with `emphasis: .menu` rows whose outcomes are `.perform(...)`.

### 5. Options: SettingsStore + Keychain migration

#### SettingKey factory

```swift
// Sources/Core/Settings/SettingKey.swift
public extension SettingKey where Value == String {
    /// Canonical non-secret option key. Name MUST remain:
    ///   "action.<actionID>.option.<optionID>"
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}

public enum ActionOptionKey {
    public static func defaultsKey(actionID: String, optionID: String) -> String {
        "action.\(actionID).option.\(optionID)"
    }
    public static func keychainAccount(actionID: String, optionID: String) -> String {
        // Same string as legacy defaults key so mental model stays one namespace;
        // storage backend differs by type.
        defaultsKey(actionID: actionID, optionID: optionID)
    }
}
```

#### Option value access protocol (Core)

```swift
// Sources/Core/Settings/ActionOptionStore.swift
public protocol ActionOptionReading: Sendable {
    func stringValue(actionID: String, option: ExtensionOption) -> String
}

public protocol ActionOptionWriting: Sendable {
    func setStringValue(_ value: String, actionID: String, option: ExtensionOption)
    func clearValue(actionID: String, option: ExtensionOption)
}

/// Default non-secret reader/writer using SettingsStore only.
public struct SettingsActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable {
    private let store: SettingsStore
    public init(store: SettingsStore = DefaultSettingsStore.shared) { self.store = store }

    public func stringValue(actionID: String, option: ExtensionOption) -> String {
        precondition(option.type != .secret, "Secrets must use Keychain-backed store")
        let key = SettingKey.actionOption(actionID: actionID, optionID: option.identifier,
                                          default: option.defaultValue ?? "")
        let value = store.get(key)
        return value.isEmpty ? (option.defaultValue ?? "") : value
    }
    ...
}
```

#### App Keychain-backed composite (App target)

```swift
// Sources/OpenClip/Platform/Extensions/KeychainActionOptionStore.swift
public struct KeychainActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable {
    private let settings: SettingsActionOptionStore
    public func stringValue(actionID: String, option: ExtensionOption) -> String {
        if option.type == .secret {
            let account = ActionOptionKey.keychainAccount(actionID: actionID, optionID: option.identifier)
            if let s = KeychainStore.get(account: account), !s.isEmpty { return s }
            return option.defaultValue ?? ""
        }
        return settings.stringValue(actionID: actionID, option: option)
    }
    public func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        if option.type == .secret {
            let account = ActionOptionKey.keychainAccount(...)
            if value.isEmpty { _ = KeychainStore.delete(account: account) }
            else { _ = KeychainStore.set(value, account: account) }
            // Ensure we do not leave a plaintext copy in UserDefaults.
            UserDefaults.standard.removeObject(forKey: account) // migration scrub only; no new reads
            return
        }
        settings.setStringValue(value, actionID: actionID, option: option)
    }
}
```

**Migration algorithm** (run once per option read if secret):

1. If Keychain has value → use it.
2. Else if legacy UserDefaults has value → write to Keychain, delete UserDefaults key, use value.
3. Else → default.

Non-secret options: already in UserDefaults under the same key; `DefaultSettingsStore.get` reads them with no migration needed.

**Accept dependencies:** `JavaScriptAction` gains `optionStore: any ActionOptionReading` (default composite). Tests inject a fake in-memory store — never touch `.standard` in tests going forward (`GoldenExtensionPlatformTests` currently sets `UserDefaults.standard` — update in Phase 1).

#### Metadata fix for `.multiple`

```swift
// ExtensionOptionMetadata — add
public let values: [String]?   // decode "values" | "options" | "Options"

// DefaultActionFactory mapping:
ExtensionOption(..., options: opt.values)
```

#### Per-action options merge

```swift
func mergedOptions(manifest: ExtensionMetadata, action: ExtensionActionMetadata) -> [ExtensionOption] {
    var map: [String: ExtensionOption] = [:]
    for o in manifest.options ?? [] { map[o.identifier] = convert(o) }
    for o in action.options ?? [] { map[o.identifier] = convert(o) } // action wins
    return Array(map.values)
}
```

### 6. Declarative after-behavior & stay-visible

Factory wraps created actions in a thin Core adapter **or** each action applies post-processing:

```swift
// Sources/Core/Actions/ActionResultAdapter.swift
public enum ActionResultAdapter {
    public static func apply(
        raw: ActionResult,
        after: ActionAfterBehavior,
        stayVisible: Bool,
        title: String,
        icon: String?
    ) -> ActionResult {
        let normalized: ActionResult
        switch (after, raw) {
        case (.copyResult, .paste(let s)), (.copyResult, .copy(let s)):
            normalized = .copy(s)
        case (.pasteResult, .copy(let s)), (.pasteResult, .paste(let s)):
            normalized = .paste(s)
        case (.showResult, .copy(let s)), (.showResult, .paste(let s)):
            normalized = .showBubble(BubbleContent(
                title: title, icon: icon, rows: [.text(s)],
                footer: [
                    BubbleOption(title: "Paste", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste(s))),
                    BubbleOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy(s)))
                ],
                emphasis: .result
            ))
        case (.none, _):
            normalized = .success
        default:
            normalized = raw
        }
        if stayVisible, normalized.dismissesPopup {
            return .keepVisible(normalized)
        }
        return normalized
    }
}
```

Shell JSON protocol expansion (stdout):

```json
{"type":"paste","value":"..."}
{"type":"copy","value":"..."}
{"type":"openURL","value":"https://..."}
{"type":"showBubble","title":"...","body":"...","footer":["paste","copy"]}
{"type":"status","message":"Done","style":"success"}
{"type":"keepVisible","effect":{"type":"copy","value":"..."}}
{"type":"configure","missing":["apiKey"],"reason":"Sign in"}
```

Decode in `ScriptAction` → `ActionResult`. Unknown types → `.success` (current default path).

### 7. New action kinds

| Kind | Type location | `perform` returns | Notes |
| :--- | :--- | :--- | :--- |
| `url` | Core `URLTemplateAction` | `.openURL` | Existing; add rules + `{matched}` placeholder |
| `scriptFile` / shell file | Core `ScriptAction` | JSON/plain stdout | Watchdog stays |
| `shellInline` | Core `CustomAction.shellScript` or dedicated | paste/copy | Watchdog stays |
| `applescript` | App `AppleScriptAction` | copy/success | Optional after-adapter |
| `js` | App `JavaScriptAction` | full host results | Live API |
| `keyPress` | App `KeyPressAction` | `.keyPress(spec)` | Handler posts CGEvent |
| `service` | App `NamedServiceAction` or reuse | `.showServices` or named | Named service best-effort via Services menu / pasteboard |
| `shortcut` | App `ShortcutAction` | `.runShortcut(name:input:)` | `shortcuts` CLI or AppleScript; **must** use timeout watchdog |

```swift
// Sources/OpenClip/Actions/KeyPressAction.swift
public struct KeyPressAction: Action {
    public let id, title: String
    public let icon: ActionIcon
    public let spec: KeyPressSpec
    public let rules: ExtensionActionRules
    public let chrome: ActionChrome
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .keyPress(spec)
    }
}

// Sources/OpenClip/Actions/ShortcutAction.swift
public struct ShortcutAction: Action {
    public let shortcutName: String
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .runShortcut(name: shortcutName, input: context.match?.matchedText ?? context.selection.text)
    }
}
```

Handler additions in `DefaultActionResultHandler`:

```swift
case .keyPress(let spec):
    simulateKeyPress(spec)  // generalize existing simulateKeyShortcut

case .runShortcut(let name, let input):
    try await runShortcutsCLI(name: name, input: input)  // Process + TimeoutFlag

case .showBubble, .showStatus, .openConfiguration, .keepVisible, .sequence:
    // no-op in handler — PopupWindowController owns these
    break
```

### 8. JavaScript host API (`openclip.*`)

Rewrite the bridge in a dedicated type for testability:

```swift
// Sources/OpenClip/Actions/OpenClipJSHost.swift
@MainActor
public final class OpenClipJSHost {
    public struct Request: Sendable {
        public var actionID: String
        public var scriptCode: String
        public var context: ActionContext
        public var options: [ExtensionOption]
        public var optionStore: any ActionOptionReading
        public var rules: ExtensionActionRules
    }

    public struct Collected: Sendable {
        public var openURL: URL?
        public var paste: String?
        public var copy: String?
        public var cut: String?
        public var bubble: BubbleContent?
        public var status: StatusFeedback?
        public var configuration: ConfigurationRequest?
        public var keyPress: KeyPressSpec?
        public var shortcutName: String?
        public var keepVisible: Bool
        public var notification: (title: String, body: String)?
        public var returnValue: String?
    }

    public func run(_ request: Request) throws -> ActionResult
}
```

**JS surface (documented for authors):**

```javascript
// Read-only context
openclip.input.text              // full selection
openclip.input.matchedText       // regex match or full text
openclip.input.captures          // string[]
openclip.input.app.bundleID
openclip.input.app.name
openclip.options.<id>            // non-secret + secret values (secrets readable at runtime only in-process)
openclip.option(id)              // functional form

// Effects (last-writer or explicit finish() wins — define: queue into sequence)
openclip.copy(text)
openclip.paste(text)
openclip.cut(text)
openclip.openURL(urlString)
openclip.keyPress(key, modifiersArray)
openclip.runShortcut(name)
openclip.notify(title, message)           // maps to user notification (UNUserNotificationCenter)
openclip.showStatus(message, style)       // "success"|"error"|"info"
openclip.showBubble({
  title, icon, subtitle,
  body,                    // string → rows: [.text]
  rows,                    // optional advanced: [{type:"text", value}, {type:"option", ...}]
  footer: ["paste","copy"] // preset footer buttons operating on `body`
           | [{title, icon, action: "paste"|"copy", value?}],
  emphasis: "result"|"menu"|"info"
})
openclip.keepVisible()                    // flag
openclip.requireConfiguration({
  reason: "Add your API key",
  missing: ["apiKey"]
})

// Entry: function action(selection, options) { ... return string|null|object }
// object return: { type: "copy"|"paste"|..., value, stayVisible?, bubble? }
```

**Result resolution order** (deterministic):

1. If `requireConfiguration` called → `.openConfiguration`.
2. Else if `showBubble` collected → `.showBubble` (± keepVisible).
3. Else if status only → `.showStatus`.
4. Else if openURL / paste / copy / cut / keyPress / shortcut → corresponding case (± keepVisible).
5. Else if function return string → apply `after` behavior (default `.copy` for JS today; preserve: current code returns `.copy(resultString)`).
6. Else `.success`.

Multiple effect calls → `.sequence([...])` in call order.

**Concurrency:** JSC is main-actor bound today (`JavaScriptAction` is `@MainActor`). Keep that; do not evaluate JS off-main without a documented isolation model. `OnceGate` not required for sync JSC eval; required if any async host callback is added later.

**Remove** direct `UserDefaults` and deprecated `NSUserNotification` in favor of option store + `UNUserNotificationCenter` (or hand notification off as a result for the handler — prefer handler so Core/JS stay testable).

### 9. Popup & presentation flow

```mermaid
sequenceDiagram
  participant User
  participant Popup as PopupWindowController
  participant Reg as ActionRegistry
  participant Act as Action
  participant H as ActionResultHandler
  participant Prefs as Preferences/EditActionSheet

  User->>Popup: selection / hotkey
  Popup->>Reg: resolveActions(context)
  Reg->>Reg: availableActions + isEnabled + MatchInfo
  User->>Popup: click action
  Popup->>Popup: rebuild ActionContext with match
  Popup->>Act: perform(matchedContext)
  Act-->>Popup: ActionResult
  alt showBubble / showStatus / openConfiguration / keepVisible
    Popup->>Popup: handle without hide() (or selective)
    opt openConfiguration
      Popup->>Prefs: present EditActionSheet(action)
    end
    opt showBubble
      Popup->>Popup: showBubble(blocksDismiss: true)
    end
  else dismissing effect
    Popup->>H: handle(effect)
    Popup->>Popup: hide()
  end
```

**Concrete `PopupWindowController` changes:**

```swift
// Today:
onResult: { result in
    self?.handleResult(result)
    self?.hide()
}

// After:
onResult: { result in
    self?.handleActionResult(result)
}

private func handleActionResult(_ result: ActionResult) {
    switch result {
    case .showBubble(let content):
        showBubble(content: content, blocksDismiss: true, ...) { outcome in
            if case .perform(let inner) = outcome {
                handleActionResult(inner)
            }
        } onClose: { hideBubble() }
        // bar stays (do not hide)

    case .showStatus(let feedback):
        presentStatusHUD(feedback)  // small app-owned view; auto-fade
        // bar stays

    case .openConfiguration(let req):
        hide()  // or stay — prefer hide bar, open prefs
        presentConfiguration(for: req.actionID, missing: req.missingOptionIDs, reason: req.reason)

    case .keepVisible(let inner):
        handleEffect(inner)  // handler only
        // do not hide

    case .sequence(let items):
        for item in items { handleActionResult(item) }

    default:
        handleEffect(result)
        if result.dismissesPopup { hide() }
    }
}

private func presentConfiguration(for actionID: String, ...) {
    // Lookup action from ActionCoordinator.shared.actions by id — data driven.
    // Post notification or call StatusBarController / Preferences entry point.
    NotificationCenter.default.post(
        name: .openClipOpenActionConfiguration,
        object: nil,
        userInfo: ["actionID": actionID, "missing": missing, "reason": reason as Any]
    )
}
```

No `switch action.id`. Preferences observes the notification, finds the action, presents `EditActionSheet(action:)`.

**Status HUD:** minimal SwiftUI overlay inside the existing bubble panel or a third tiny panel; uses design tokens only (symbol + caption). Not a free-form canvas.

**Pin / stay-visible interaction with existing `bubbleBlocksDismiss`:**  
`keepVisible` alone leaves the **bar** up and continues distance-dismiss unless a blocking bubble is showing. `showBubble` sets `bubbleBlocksDismiss = true` (existing). Manifest `stayVisible: true` ≈ `.keepVisible` wrapper. Optional future: `pin: true` could disable distance dismiss for the bar — defer to Phase 6 if needed; not required for MVP if bubble path covers rich results.

### 10. Settings UI

`DynamicActionConfigView`:

- Replace `@AppStorage` with `@State` + `ActionOptionReading/Writing` injected (default `KeychainActionOptionStore`).
- On appear, load values; on change, write through store.
- `.secret` → `SecureField`; never mirror into UserDefaults.
- Show banner when opened via `ConfigurationRequest` (reason + highlight missing option IDs).

`EditActionSheet` already embeds `DynamicActionConfigView` when `action.actionOptions` non-empty — keep that path; ensure extension actions always expose merged options on `actionOptions`.

### 11. TextPlaceholderEngine expansion

```swift
// Support in URL templates and shell env:
// {text}, {query} — existing
// {matched} — matchedText
// {capture1}, {capture2}, ... or {1}, {2}
// {bundleID}
public static func replacePlaceholders(
    in template: String,
    context: ActionContext,
    urlEncode: Bool
) -> String
```

Deprecate bare `(template, text)` overload gradually by implementing it as matched=text, no captures.

Shell env additions:

```text
OPENCLIP_TEXT          // existing
OPENCLIP_MATCHED
OPENCLIP_CAPTURE_1 ...
OPENCLIP_BUNDLE_ID
OPENCLIP_OPTION_<ID>   // non-secret only (secrets intentionally omitted from env)
```

### 12. Chrome & gesture policy

No string matching. Optional expansion:

```swift
public enum ActionChrome.PopupBehavior {
    case perform
    case showTransformMenu
    case provideCompletions
    case showResultBubble   // optional: single-click shows bubble if action conforms / rules.after == showResult
}
```

Only add `showResultBubble` if declarative `after: show-result` should change click behavior without `ResultBubbleProviding`. Prefer: `after: show-result` still runs perform, which returns `.showBubble` — single click path already works once popup handles that result. **No chrome change required for MVP.**

Long-press `ResultBubbleProviding` remains opt-in for builtins (Calculate). JS actions can implement `ResultBubbleProviding` by precomputing a bubble in `makeBubble` if desired later; not required in Phase 1–4.

### 13. Trust & security (summary)

- Extensions run with full user privileges (shell, AppleScript, JSC, keypress).
- Install path stays user-initiated (`installExtension`, store ZIP).
- Secrets in Keychain; never log option values.
- Regex from manifests: use non-catastrophic patterns; consider a match timeout (e.g. 50ms) in `ActionVisibility` to avoid ReDoS freezing the popup — implement simple time-bound or length cap (`Constants.maxTextLength` already exists; add `maxRegexInputLength` e.g. 100_000).
- `shortcuts run` and shell still under `Constants.scriptTimeout`.

---

## API / Interface Changes

### Before / after (critical)

**ActionContext**

```swift
// Before
public struct ActionContext {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
}

// After
public struct ActionContext {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    public let match: ActionMatchInfo?  // new, default nil
}
```

**ActionResult** — additive cases only (§4). Existing switches must gain `default` or explicit handling — update:

- `DefaultActionResultHandler.handle`
- `PopupWindowController.handleResult` → `handleActionResult`
- `ActionResultHandlerTests`
- Any exhaustive switches in tests

**ActionFactory** — signature unchanged; behavior richer via metadata fields.

**JavaScriptAction**

```swift
public struct JavaScriptAction: ConfigurableAction {
    ...
    public let rules: ExtensionActionRules
    public let optionStore: any ActionOptionReading  // cannot store existential easily if struct — use
    // Better: hold option values snapshot at perform-time via injected reader parameter on perform path,
    // or final class host.
}
```

Because `Action` is `Sendable` and existentials of non-Sendable stores are painful, prefer:

```swift
public struct JavaScriptAction: ConfigurableAction {
    public let optionSnapshots provider via:
    // At perform:
    let store = ActionOptionStoreHolder.shared.reader  // App sets at launch
}
```

Cleaner DI:

```swift
// Core
public enum ActionOptionRuntime {
    nonisolated(unsafe) public static var reader: any ActionOptionReading = SettingsActionOptionStore()
}
// AppDelegate loadInitialState:
ActionOptionRuntime.reader = KeychainActionOptionStore()
```

Document as temporary composition until a fuller `AppServices` injection lands (see `AppServices.swift`). Prefer passing through `AppServices` if easy:

```swift
// AppServices already has settingsStore — add optionStore there and have JS read from a package-visible accessor set at launch.
```

**ExtensionOptionMetadata** — add `values: [String]?`.

**ExtensionActionMetadata** — add requirements, after, stayVisible, shortcutName, keyPress, serviceName, options.

---

## Data Model Changes

| Store | Key / account | Type | Migration |
| :--- | :--- | :--- | :--- |
| UserDefaults via SettingsStore | `action.<actionID>.option.<id>` | string/bool/multiple as String | None (already) |
| Keychain `com.openclip.app` | same string as account | secret | On read: UD → Keychain → delete UD |
| In-memory | n/a | test fakes | — |

No Core Data / files beyond existing manifests. No change to `action.order` / `disabledActionIDs`.

**Uninstall:** when package removed, optionally clear option keys for that package’s action IDs (best-effort enumeration of `actionOptions` before unregister). Phase 5 nice-to-have; not blocking.

---

## Alternatives Considered

### A1. Replace `ActionResult` with a structured `ActionOutcome` struct

```swift
struct ActionOutcome {
  var effects: [Effect]
  var presentation: Presentation?
  var dismiss: DismissPolicy
}
```

- **Pros:** Cleaner long-term; dismiss policy explicit.
- **Cons:** Touches every builtin, every test, `BubbleOutcome`, Calculate, AI paths in one PR; high regression risk.
- **Verdict:** Rejected for now; additive enum + `keepVisible` / `sequence` gets 90% with less churn. Revisit if sequence nesting becomes painful.

### A2. Out-of-process JS (separate XPC / node)

- **Pros:** Crash isolation.
- **Cons:** Out of scope (no sandbox program); latency; host API complexity; contradicts “in-process trusted authors.”
- **Verdict:** Rejected.

### A3. Give shell/AppleScript the same live host API via JSON-RPC on stdin

- **Pros:** One author model.
- **Cons:** Heavy protocol, timeout/partial-line issues, duplicates JSC bridge.
- **Verdict:** Rejected; expand one-shot JSON stdout instead.

### A4. WebView-based custom cards for extensions

- **Pros:** Maximum author freedom.
- **Cons:** Violates fixed presentation philosophy; security surface; design-token bypass.
- **Verdict:** Rejected (explicit non-goal).

### A5. Per-extension AppKit preferences bundles

- **Pros:** Fully custom settings UIs.
- **Cons:** Loadable code plugins beyond JS; signing; complexity.
- **Verdict:** Rejected; generated `DynamicActionConfigView` from options is the settings surface.

---

## Security & Privacy Considerations

| Threat | Severity | Mitigation |
| :--- | :--- | :--- |
| Malicious extension runs arbitrary shell | High (accepted) | Trusted-author model; user installs deliberately; document in README |
| Secret API keys in UserDefaults/backups | High | Keychain only for `.secret`; migrate + scrub |
| Secret leakage to shell env | Medium | Never export secrets as `OPENCLIP_OPTION_*` |
| ReDoS via manifest regex | Medium | Input length cap; optional match time budget |
| JS reads other actions’ options | Low | Host only injects **this** action’s options |
| Keypress spoofing / Shortcut abuse | Medium | Same trust model; timeout on Shortcut process |
| Notification content phishing | Low | App-owned notification styling; title prefix “OpenClip” |
| Zip-slip on install | Low (fixed) | Keep `Constants.isPathSafe` |

Logging: never log option values or selection text at default log levels. Errors may include action IDs only.

---

## Observability

| Signal | Where | Purpose |
| :--- | :--- | :--- |
| `os.Logger` subsystem `com.openclip.extensions` | ExtensionManager load, factory failures | Count load failures per package |
| Logger on ActionVisibility regex errors | ActionVisibility | Invalid patterns |
| Logger on JS exceptions (`JSContext.exception`) | OpenClipJSHost | Author debug; surface as `.failure` / status error |
| Logger on Shortcut/script timeout | Handler / ScriptAction | Already throws timeout NSError |
| No crash analytics required in-scope | — | — |

Debug menu / future: “Extension console” out of scope.

---

## Rollout Plan

Feature flags are optional; prefer **phased shipping behind versioned manifest fields** (old manifests keep working).

1. Ship Phase 1–2 internally; no author-facing doc change.
2. Phase 3–4: document new kinds + JS API in author notes (not this deliverable’s mandatory doc file unless asked).
3. Phase 5: secrets migration runs transparently on read.
4. Rollback: additive API — revert App handler/popup switches; old actions still return old cases.

---

## Phased Implementation Plan

Each phase: files → types → flow → options migration slice → tests → exit criteria (`xcodegen generate` if files added, quick build gate, `./scripts/test.sh <Class>`).

---

### Phase 0 — Prep & inventory (½ day)

**Intent:** Confirm baselines green; no product code.

**Files:** none (or test-only fixes if suite already red).

**Exit:** `./scripts/test.sh ExtensionManagerTests`, `DefaultActionFactoryTests`, `GoldenExtensionPlatformTests`, `SettingsStoreTests`, `ActionResultHandlerTests` pass.

---

### Phase 1 — Option keys, ActionOptionStore, purge UserDefaults from JS path

**Intent:** All extension option reads/writes go through SettingsStore; tests stop using ad-hoc `UserDefaults.standard` for options. Secrets still stored as string in SettingsStore temporarily **or** skipped until Phase 5 — **prefer**: implement full Keychain split here if small; if not, gate `.secret` writes with a TODO that still avoids @AppStorage for secrets by using a no-op warning. **This plan implements non-secret migration in Phase 1 and secrets in Phase 5** to keep the phase green and reviewable.

#### Files

| Action | Path | Target |
| :--- | :--- | :--- |
| Edit | `Sources/Core/Settings/SettingKey.swift` | Core |
| Create | `Sources/Core/Settings/ActionOptionStore.swift` | Core |
| Edit | `Sources/OpenClip/Actions/JavaScriptAction.swift` | App |
| Edit | `Sources/OpenClip/UI/Preferences/DynamicActionConfigView.swift` | App |
| Edit | `Sources/OpenClip/AppDelegate.swift` or `App/AppServices.swift` | App — set runtime reader |
| Edit | `Tests/OpenClipTests/SettingsStoreTests.swift` | Tests |
| Create | `Tests/OpenClipTests/ActionOptionStoreTests.swift` | Tests |
| Edit | `Tests/OpenClipTests/GoldenExtensionPlatformTests.swift` | Tests |

#### Types / signatures

```swift
public protocol ActionOptionReading: Sendable {
    func stringValue(actionID: String, option: ExtensionOption) -> String
}
public protocol ActionOptionWriting: Sendable {
    func setStringValue(_ value: String, actionID: String, option: ExtensionOption)
}
public struct SettingsActionOptionStore: ActionOptionReading, ActionOptionWriting, Sendable { ... }

public enum ActionOptionRuntime {
    // Set at launch from App; tests override.
    nonisolated(unsafe) public static var reader: any ActionOptionReading
    nonisolated(unsafe) public static var writer: any ActionOptionWriting
}

extension SettingKey where Value == String {
    static func actionOption(actionID: String, optionID: String, default: String = "") -> SettingKey<String>
}
```

#### Flow

Unchanged registration flow. At `JavaScriptAction.perform`, replace:

```swift
UserDefaults.standard.string(forKey: key)
```

with:

```swift
ActionOptionRuntime.reader.stringValue(actionID: id, option: opt)
```

`DynamicActionConfigView` loads/saves via writer (use `SettingsStore` publisher or explicit set on toggle).

#### Options migration

Non-secret: keys unchanged → zero data migration.  
Remove new call sites of `UserDefaults.standard` for option keys.

#### Test plan

```text
./scripts/test.sh ActionOptionStoreTests
./scripts/test.sh SettingsStoreTests
./scripts/test.sh GoldenExtensionPlatformTests
```

- In-memory fake store: set prefix → JS action returns prefixed copy.
- Assert `JavaScriptAction` source no longer references `UserDefaults.standard` (code review + test using injected store only).

#### Exit criteria

Build gate + tests above green. `rg 'UserDefaults.standard' Sources/OpenClip/Actions/JavaScriptAction.swift` empty.

---

### Phase 2 — ActionResult expansion + handler + popup dismiss policy

**Intent:** App can show bubbles/status/config/keepVisible from any action result without breaking existing builtins.

#### Files

| Action | Path |
| :--- | :--- |
| Edit | `Sources/Core/Actions/ActionResult.swift` |
| Create | `Sources/Core/Actions/StatusFeedback.swift` (or nest in ActionResult file) |
| Create | `Sources/Core/Actions/ConfigurationRequest.swift` |
| Create | `Sources/Core/Actions/KeyPressSpec.swift` |
| Edit | `Sources/Core/Actions/BubbleContent.swift` — only if `pinToBar` added (optional; skip if unused) |
| Edit | `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift` |
| Edit | `Sources/OpenClip/UI/Popup/PopupWindowController.swift` |
| Edit | `Sources/OpenClip/UI/Popup/PopupView.swift` — onResult wiring if needed |
| Edit | `Sources/OpenClip/StatusBarController.swift` or Preferences host — observe config notification |
| Create | `Tests/OpenClipTests/ActionResultDismissPolicyTests.swift` |
| Edit | `Tests/OpenClipTests/ActionResultHandlerTests.swift` |

#### Types

See §4 full signatures. Implement:

```swift
extension ActionResult {
    public var dismissesPopup: Bool { get }
}
```

#### Flow

```text
perform → ActionResult
  → PopupWindowController.handleActionResult
      → showBubble / status / openConfiguration / keepVisible / sequence
      → else DefaultActionResultHandler.handle + conditional hide()
```

`openConfiguration` posts `Notification.Name.openClipOpenActionConfiguration` with `actionID`; Preferences finds action in `ActionCoordinator.shared.actions` and presents `EditActionSheet`.

#### Options migration

None.

#### Test plan

```text
./scripts/test.sh ActionResultDismissPolicyTests
./scripts/test.sh ActionResultHandlerTests
./scripts/test.sh BuiltinActionsTests
```

- Unit-test `dismissesPopup` matrix for all cases.
- Handler: `.keyPress` with known key posts (may be hard in CI — test that handler switch does not throw; optional).
- Handler ignores `.showBubble` (no crash).
- Existing copy test still passes.

#### Exit criteria

Full `./scripts/test.sh ActionResult*` + builtins green. Manually: temporary debug action returning `.showBubble` keeps bar (dev only).

---

### Phase 3 — Visibility, MatchInfo, manifest requirements, multi-action IDs

**Intent:** Declarative visibility works for all extension actions; stable multi-action IDs; match info on context.

#### Files

| Action | Path |
| :--- | :--- |
| Create | `Sources/Core/Actions/ActionMatchInfo.swift` |
| Create | `Sources/Core/Actions/ActionVisibility.swift` |
| Create | `Sources/Core/Extensions/Manifest/ActionRequirements.swift` |
| Create | `Sources/Core/Actions/ExtensionActionRules.swift` |
| Edit | `Sources/Core/Actions/ActionContext.swift` |
| Edit | `Sources/Core/Extensions/Manifest/ExtensionManifest.swift` (`ExtensionActionMetadata`) |
| Edit | `Sources/Core/Extensions/ExtensionManager.swift` (`ExtensionOptionMetadata.values`, option decode) |
| Edit | `Sources/Core/Actions/URLTemplateAction.swift` |
| Edit | `Sources/Core/Extensions/ScriptAction.swift` |
| Edit | `Sources/OpenClip/Actions/JavaScriptAction.swift` |
| Edit | `Sources/OpenClip/Actions/AppleScriptAction.swift` |
| Edit | `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift` |
| Edit | `Sources/OpenClip/UI/Popup/PopupView.swift` (match context on perform) |
| Edit | `Sources/Core/Utils/TextPlaceholderEngine.swift` |
| Create | `Tests/OpenClipTests/ActionVisibilityTests.swift` |
| Edit | `Tests/OpenClipTests/ExtensionManifestTests.swift` |
| Edit | `Tests/OpenClipTests/DefaultActionFactoryTests.swift` |
| Create | `Tests/OpenClipTests/MultiActionExtensionTests.swift` |

#### Types

```swift
public struct ActionRequirements: Codable, Sendable, Equatable { ... }
public struct ExtensionActionRules: Sendable { ... }
public struct ActionMatchInfo: Sendable, Equatable { ... }

public enum ActionVisibility {
    public static func evaluate(requirements:legacyRegex:context:) -> (Bool, ActionMatchInfo)
}
```

Factory ID algorithm as in §2. Apply `rules` to every created extension action.  
`URLTemplateAction` delegates `isEnabled` to `ActionVisibility` (legacy `regex` maps into requirements).

#### Flow

```text
ExtensionManager.scan → factory.createAction (with rules + merged options)
  → onRegister → Registry
Popup resolveActions → action.isEnabled (Visibility)
Click → Visibility.evaluate again → ActionContext(match:) → perform
URL placeholders use match
```

#### Options migration

Decode `values` for multiple; factory passes `options:` into `ExtensionOption`. Still package-level + start per-action merge.

#### Test plan

```text
./scripts/test.sh ActionVisibilityTests
./scripts/test.sh ExtensionManifestTests
./scripts/test.sh MultiActionExtensionTests
./scripts/test.sh DefaultActionFactoryTests
./scripts/test.sh GoldenExtensionPlatformTests
```

Cases:

- Allow-list apps enable/disable.
- Negated regex.
- Captures `[("a@b.com", ["a","b.com"])]` style.
- Manifest with 3 actions → 3 registry IDs `pkg.a`, `pkg.b`, `pkg.action.2`.
- URL `{matched}` encoding.

#### Exit criteria

Build + listed tests green. Multi-action package loads without title-based ID instability.

---

### Phase 4 — JS host v2 + after-behavior adapter + shell JSON expansion

**Intent:** Authors can build rich JS extensions; declarative `after` / `stayVisible`; shell can return bubble/status JSON.

#### Files

| Action | Path |
| :--- | :--- |
| Create | `Sources/OpenClip/Actions/OpenClipJSHost.swift` |
| Edit | `Sources/OpenClip/Actions/JavaScriptAction.swift` — delegate to host |
| Create | `Sources/Core/Actions/ActionResultAdapter.swift` |
| Edit | `Sources/Core/Extensions/ScriptAction.swift` — expand JSON decode |
| Edit | `Sources/Core/Extensions/Manifest/ExtensionActionKind.swift` if needed |
| Edit | `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift` — wire after/stayVisible |
| Create | `Tests/OpenClipTests/OpenClipJSHostTests.swift` |
| Create | `Tests/OpenClipTests/ActionResultAdapterTests.swift` |
| Edit | `Tests/OpenClipTests/ScriptActionExecutionTests.swift` |
| Edit | `Tests/OpenClipTests/GoldenExtensionPlatformTests.swift` |

#### Types

`OpenClipJSHost` as in §8.  
`ActionAfterBehavior` enum.  
Script JSON DTOs:

```swift
struct ScriptJSONOutput: Decodable {
    var type: String
    var value: String?
    var title: String?
    var body: String?
    var message: String?
    var style: String?
    var missing: [String]?
    var reason: String?
    var effect: ScriptJSONOutput?  // for keepVisible wrap
    var footer: [String]?
}
```

#### Flow

```text
JS perform → OpenClipJSHost.run → ActionResult
  → ActionResultAdapter.apply(after, stayVisible)
  → Popup handleActionResult
Shell stdout JSON → ScriptAction map → Adapter → same
```

#### Options migration

Host reads options exclusively via `ActionOptionRuntime.reader`.

#### Test plan

```text
./scripts/test.sh OpenClipJSHostTests
./scripts/test.sh ActionResultAdapterTests
./scripts/test.sh ScriptActionExecutionTests
./scripts/test.sh GoldenExtensionPlatformTests
```

JS tests (MainActor):

- `openclip.paste` → `.paste`
- `showBubble` → `.showBubble` with footer presets
- `requireConfiguration` → `.openConfiguration` with actionID
- `keepVisible` + copy → `.keepVisible(.copy)`
- `input.captures` exposed
- Exception → `.failure` or status error

Shell:

- showBubble JSON → `.showBubble`
- keepVisible JSON → wrapper

#### Exit criteria

Build + tests green. Golden suite extended with one JS bubble extension.

---

### Phase 5 — Secrets (Keychain), settings-required UX, DynamicActionConfig polish

**Intent:** `.secret` never persists in UserDefaults; configuration request opens sheet with highlight.

#### Files

| Action | Path |
| :--- | :--- |
| Create | `Sources/OpenClip/Platform/Extensions/KeychainActionOptionStore.swift` |
| Edit | `Sources/OpenClip/AppDelegate.swift` / `AppServices.swift` — install composite store |
| Edit | `Sources/OpenClip/UI/Preferences/DynamicActionConfigView.swift` — secret path + missing highlight |
| Edit | `Sources/OpenClip/UI/Preferences/EditActionSheet.swift` — accept reason banner |
| Edit | `Sources/OpenClip/StatusBarController.swift` or prefs router — notification observer |
| Edit | `Sources/Core/Actions/ActionVisibility.swift` — optional soft-disable vs configure-on-run |
| Create | `Tests/OpenClipTests/KeychainActionOptionStoreTests.swift` (use unique account prefix; delete in tearDown) |

#### Policy: missing required options

**Chosen:** Action remains **visible** if other requirements pass; `perform` short-circuits:

```swift
let missing = ActionVisibility.missingRequiredOptions(...)
if !missing.isEmpty {
  return .openConfiguration(ConfigurationRequest(actionID: id, reason: "...", missingOptionIDs: missing))
}
```

Alternative (hide when missing) is worse UX — user cannot discover the action.

#### Options migration

Full secret migration on read (UD → Keychain → scrub). One-shot `migrateAllSecrets(for actions:)` on extension load optional.

#### Test plan

```text
./scripts/test.sh KeychainActionOptionStoreTests
./scripts/test.sh ActionOptionStoreTests
./scripts/test.sh OpenClipJSHostTests
```

- Write secret via store → Keychain hit, UserDefaults nil.
- Legacy UD secret migrates on first read.
- JS `requireConfiguration` integration already in Phase 4; add missing requiredOptions auto path test.

#### Exit criteria

No secret values in `defaults read` for test accounts. Build + tests green.

---

### Phase 6 — New kinds (keyPress, shortcut, service) + env/placeholder completion + polish

**Intent:** Full kind matrix; author-complete.

#### Files

| Action | Path |
| :--- | :--- |
| Edit | `Sources/Core/Extensions/Manifest/ExtensionActionKind.swift` |
| Edit | `Sources/Core/Extensions/Manifest/ExtensionManifest.swift` |
| Create | `Sources/OpenClip/Actions/KeyPressAction.swift` |
| Create | `Sources/OpenClip/Actions/ShortcutAction.swift` |
| Create | `Sources/OpenClip/Actions/NamedServiceAction.swift` (optional; or map service → showServices) |
| Edit | `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift` |
| Edit | `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift` — shortcut process + keypress |
| Edit | `Sources/Core/Extensions/ScriptAction.swift` — extra env vars |
| Edit | `Sources/Core/Extensions/OpenClipSnippetParser.swift` — optional header keys for new kinds (keep pure parser) |
| Create | `Tests/OpenClipTests/NewExtensionKindTests.swift` |
| Edit | `Tests/OpenClipTests/DefaultActionFactoryTests.swift` |

#### Shortcut execution

```swift
// Prefer: /usr/bin/shortcuts run "Name" 
// Pass input via stdin or -i if available; wrap TimeoutFlag + Constants.scriptTimeout
```

#### Service

MVP: `type: service` without name → `.showServices(text)` (existing).  
Named service: best-effort `NSPerformService` if linked; otherwise document limitation and fall back to picker.

#### Test plan

```text
./scripts/test.sh NewExtensionKindTests
./scripts/test.sh DefaultActionFactoryTests
./scripts/test.sh ActionResultHandlerTests
timeout -k 5 60 xcodebuild ... build
./scripts/test.sh   # full suite once at end
```

Factory routing unit tests do not need to invoke real Shortcuts in CI — assert type and that `perform` returns `.runShortcut`. Handler test can skip CLI if `shortcuts` missing.

#### Exit criteria

All phases’ tests green; full suite once. `xcodegen generate` committed if project.yml uses folder globs (OpenClip typically regenerates on new files — **mandatory** per AGENTS.md).

---

## PR Plan

Ordered PRs align with phases. Each PR is independently reviewable and green.

| PR | Title | Depends on | Primary files | Description |
| :--- | :--- | :--- | :--- | :--- |
| **PR1** | `ext: route action options through SettingsStore` | — | `SettingKey.swift`, `ActionOptionStore.swift`, `JavaScriptAction.swift`, `DynamicActionConfigView.swift`, tests | Phase 1. No author-facing behavior change except testability. |
| **PR2** | `ext: additive ActionResult presentation cases + popup dismiss policy` | PR1 | `ActionResult.swift`, `ActionResultHandler.swift`, `PopupWindowController.swift`, tests | Phase 2. Builtins unchanged; infrastructure for rich results. |
| **PR3** | `ext: ActionVisibility, MatchInfo, multi-action stable IDs` | PR2 | `ActionVisibility.swift`, `ActionContext.swift`, manifest types, factory, popup perform path, tests | Phase 3. Declarative requirements. |
| **PR4** | `ext: OpenClip JS host v2 + result adapter + shell JSON` | PR3 | `OpenClipJSHost.swift`, `JavaScriptAction.swift`, `ActionResultAdapter.swift`, `ScriptAction.swift`, tests | Phase 4. Author-facing JS power. |
| **PR5** | `ext: Keychain secrets + openConfiguration UX` | PR4 | `KeychainActionOptionStore.swift`, Dynamic/Edit sheets, AppServices, tests | Phase 5. Security fix for secrets. |
| **PR6** | `ext: keyPress, shortcut, service action kinds` | PR5 | new action types, factory, handler, tests | Phase 6. Completes kind matrix. |

**PR hygiene:**

- Run `xcodegen generate` when adding/removing Swift files.
- Quick compile gate before full suite.
- Do not introduce `import AppKit` in Core.
- Do not call `ActionRegistry.shared` from `ExtensionManager`.
- Update file-level doc comments when responsibilities change.
- Touch `Agents.md` only if a new hard rule emerges (e.g. “secrets always Keychain”) — prefer one bullet under §4 after PR5.

---

## Risk Register

| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| Exhaustive switch compile breaks on `ActionResult` | Medium | Fix all switches in same PR2; search `switch.*ActionResult` / `case \.showServices` |
| `nonisolated(unsafe)` option runtime globals | Low | Mirror existing singleton patterns; tests set/reset in tearDown |
| Popup never-key rule vs configuration sheet | Medium | Configuration opens standard Preferences window (key OK); popup hides first |
| Shortcut CLI differences across macOS versions | Medium | Feature-detect binary; failure → `.showStatus` error |
| JS bridge injection typos | Low | Centralize in `OpenClipJSHost`; golden tests |
| Multi-action ID change breaks user `action.order` / disabled sets | Medium | Prefer explicit manifest `id`; document that title-based IDs were unstable; optional migration map title→index not worth it |
| Test suite hang in CI | Low (known) | Prefer gated build + targeted `scripts/test.sh Class` per phase; full suite at end |
| Secret briefly in UD during migration race | Low | Migrate on read under main actor; scrub immediately |

---

## Open Questions

1. **Named Services API:** Is `NSPerformService` acceptable, or is the generic picker enough for v1? (*Recommendation: picker MVP in PR6; named as follow-up.*)
2. **Status HUD placement:** Reuse bubble panel vs. ephemeral toast under bar? (*Recommendation: ephemeral toast using same material tokens, auto-dismiss 1.5s, does not set `bubbleBlocksDismiss`.*)
3. **JS `setOption`:** Should scripts write options at runtime? (*Recommendation: no in v1 — settings UI is the write path; avoids surprising persistence.*)
4. **Per-package vs per-action disabled state:** Today disable is per action ID — sufficient?
5. **Snippet headers for requirements:** Worth teaching `# regex:` / `# apps:` in `OpenClipSnippetParser` in PR3 or defer? (*Recommendation: defer to PR6; parser stays minimal.*)
6. **`ActionOptionRuntime` vs `AppServices` injection:** Prefer expanding `AppServices` if call sites can accept it without protocol witness explosion on `Action` structs.

---

## References (code only — no prior extension specs)

| Topic | Path |
| :--- | :--- |
| Action protocol | `Sources/Core/Actions/Action.swift` |
| ActionResult | `Sources/Core/Actions/ActionResult.swift` |
| BubbleContent | `Sources/Core/Actions/BubbleContent.swift` |
| ActionChrome / gesture policy | `Sources/Core/Actions/ActionChrome.swift`, `PopupGesturePolicy.swift` |
| Registry / Coordinator | `Sources/Core/Actions/ActionRegistry.swift`, `ActionCoordinator.swift` |
| Extension manager / metadata | `Sources/Core/Extensions/ExtensionManager.swift` |
| Manifest / kinds | `Sources/Core/Extensions/Manifest/ExtensionManifest.swift`, `ExtensionActionKind.swift` |
| Snippet parser | `Sources/Core/Extensions/OpenClipSnippetParser.swift` |
| ScriptAction + watchdog | `Sources/Core/Extensions/ScriptAction.swift`, `CustomAction.swift` (`OnceGate`, `TimeoutFlag`) |
| Settings door | `Sources/Core/Settings/SettingKey.swift`, `SettingsStore.swift` |
| Factory | `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift` |
| JS / AppleScript | `Sources/OpenClip/Actions/JavaScriptAction.swift`, `AppleScriptAction.swift` |
| Result handler | `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift` |
| Popup | `Sources/OpenClip/UI/Popup/PopupWindowController.swift`, `BubbleCardView.swift`, `PopupView.swift` |
| Options UI | `Sources/OpenClip/UI/Preferences/DynamicActionConfigView.swift`, `EditActionSheet.swift` |
| Keychain pattern | `Sources/OpenClip/Platform/KeychainStore.swift`, `AI/AIServiceManager.swift` |
| Tests / runner | `Tests/OpenClipTests/*`, `scripts/test.sh` |
| Hard rules | `Agents.md` §4–§5 |

---

## Revision Summary

_Initial draft (2026-08-03). No review_file supplied; document written from code inspection of Core Actions/Extensions/Settings and App factory, runtimes, popup, and tests. Ready for implementation starting at Phase 1 / PR1._
