# App rules

[`AppRule`](../../Sources/Core/Rules/AppRule.swift) and [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift) let you change how OpenClip behaves in specific apps. A rule can turn OpenClip off in an app, limit it to the hotkey, choose how the selection is read, or force text to be copied instead of pasted.

## Rule file format

Rules live in a JSON file such as `~/.openclip/rules.json`, which follows `RuleEngineConfig`:

```jsonc
{
  "rules": [
    {
      "bundle-identifiers": ["com.example.game"],
      "disabled": true
    },
    {
      "bundle-identifiers": ["com.example.editor"],
      "hotkey-only": true
    },
    {
      "bundle-identifiers": ["com.example.terminal"],
      "deny-paste": true,
      "retrieval-mode": "menu-copy"
    },
    {
      "bundle-identifiers": ["com.example.app"],
      "gate": {
        "skipRoles": [],
        "allowedCursors": ["beam", "arrow", "pointingHand", "unknown"]
      }
    }
  ]
}
```

## Properties

| JSON key | Code identifier | Type | What it does |
| :--- | :--- | :--- | :--- |
| `bundle-identifiers` | `bundleIdentifiers` | Array | The apps the rule applies to. Entries can be bundle IDs, `process:<name>` or `path:<executable>` patterns for apps without a bundle ID, wildcards, or group aliases. |
| `disabled` | `disabled` | Bool | Turns OpenClip off in the app: no popup, and the hotkey is ignored. |
| `hotkey-only` | `hotkeyOnly` | Bool | Stops the popup from appearing when text is selected. OpenClip opens only from the global hotkey (`⌥⌘C`). |
| `deny-paste` | `denyPaste` | Bool | Delivers text as a copy even when the app offers a Paste command, as terminals do. |
| `retrieval-mode` | `retrievalMode` | Enum | How OpenClip reads the selection: `ax-text-control` (default), `ax-web-area`, `browser-script`, `menu-copy`, or `keyboard-copy`. See the next table. |
| `gate` | `gate` | Object | Checks that run before reading: `skipRoles` lists AX roles that can never hold a selection, and `allowedCursors` lists cursor types that suggest a text area. See [`SelectionGatePolicy`](../../Sources/Core/Rules/SelectionGatePolicy.swift). |
| `use-menu-copy` | `useMenuCopy` | Bool | Legacy alias. `true` means `retrieval-mode: "menu-copy"` (read through the Edit > Copy menu item), but only if the rule has no `retrieval-mode` and the built-in catalog hasn't already given the app a different mode. Use `retrieval-mode` in new rules. |

### Retrieval modes

| Value | How it reads | Used for |
| :--- | :--- | :--- |
| `ax-text-control` | Reads `kAXSelectedTextAttribute` directly, with no pasteboard side effects. This is the default. | Standard native text controls |
| `ax-web-area` | Reads the AX web area through text-marker ranges, retrying until the page settles and walking the DOM when needed. | Browsers (Safari, Chrome, Firefox, Arc) and embedded web content |
| `browser-script` | Legacy alias. It used to run AppleScript in browsers. It now maps to `ax-web-area` with a `keyboard-copy` fallback, which is faster and needs no automation permission prompt. | Supported browsers |
| `menu-copy` | Presses the Edit > Copy menu item through AX, then restores the pasteboard. | Terminal emulators and command-line tools |
| `keyboard-copy` | Sends a ⌘C key event, then restores the pasteboard. | Custom code editors and Electron apps |

These match the per-app defaults in the built-in catalog (`DefaultAppRules.catalog`). A rule overrides only the keys it sets, so a rule with just `gate` leaves the app's default `retrieval-mode` alone.

## Blocked by default

`DefaultAppRules.disabledApps` is a built-in `disabled: true` rule for apps where OpenClip has nothing useful to read: virtual machines and remote desktops (Parallels, VMware, UTM, VirtualBox, Microsoft Remote Desktop, Citrix, Amazon Workspaces, Screen Sharing, Screens), emulators and canvas-first apps (iOS Simulator, Android emulators, Unity, Blizzard games, CrossOver, Adobe apps, Pixelmator), and a few apps that expose no text selection.

These are ordinary rules, not a separate blocklist. The menu bar shows **Disabled in &lt;App&gt;** for them, and turning that item off writes a user rule with `disabled: false` that overrides the default. The App Rules page sees the same user rule.

`AppFilter` is narrower and not user-editable. It only holds identities that must never be targeted: OpenClip itself, the Dock, SystemUIServer, the character palette, PopClip, and the bundle-less Java launcher.

## Matching apps

### Bundle IDs

A plain entry matches the app's bundle identifier. Apps without one, such as command-line tools and SDL apps like [scrcpy](https://github.com/genymobile/scrcpy), use scoped identifiers:

- `"process:scrcpy"` matches the process's executable or localized name. Matching ignores case, and `*` wildcards work (`"process:scr*"`).
- `"path:/opt/homebrew/bin/scrcpy"` matches the executable path, and `*` wildcards work (`"path:/opt/tools/*"`).

The App Rules page and the menu bar's **Disable in &lt;App&gt;** item write `process:` rules for apps without a bundle ID.

### Wildcards

`RuleEngine` supports prefix wildcards with `.*` and a global `*`:

- `"com.example.*"` matches `com.example.app1`, `com.example.app2`, and so on.
- `"*"` matches every app, including those without a bundle ID.

### Group aliases

| Alias | Expands to |
| :--- | :--- |
| `:menu-copy-apps:` | Every terminal app set up for menu-based copy in `DefaultAppRules.menuCopyApps`. |

## How a rule is applied

1. When a selection is detected, the trigger sites (`MacSelectionMonitor` and `HotkeyManager`) call `RuleEngine.shared.resolvePolicies(for: appIdentity)`.
2. `RuleEngine` compares the app's identity with the effective rules (default rules plus your rules). Plain patterns match the bundle ID, `process:` patterns the process name, and `path:` patterns the executable path, with `.*` prefix and `*` wildcards.
3. Matching settings override the default `AppPolicyContext` values. The resolved `retrieval-mode` and `gate` go to `SelectionRetrievalCoordinator`, which reads the selection.
4. A legacy `use-menu-copy: true` becomes `retrieval-mode: "menu-copy"` only when the rule has no explicit `retrieval-mode` and the built-in catalog hasn't already given the app a different mode.
5. If `denyPaste: true` applies to the frontmost app, paste delivery falls back to copy and the Paste and Cut actions are hidden from the popup bar, through the shared `PasteAvailability` decision.
