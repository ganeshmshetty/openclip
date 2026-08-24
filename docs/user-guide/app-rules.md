# Application-Specific Policy Rules (`AppRule`)

OpenClip allows configuring application-specific behavior rules through [`AppRule`](../../Sources/Core/Rules/AppRule.swift) and [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift). App rules control how OpenClip retrieves text and delivers it (paste vs copy) when specific target macOS applications are active.

---

## JSON Configuration Format (`rules.json`)

Rules are stored in JSON configuration files (such as `~/.openclip/rules.json`) conforming to `RuleEngineConfig`:

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

---

## Policy Properties Reference

| Property Key in JSON | Code Identifier | Type | Description |
| :--- | :--- | :--- | :--- |
| `bundle-identifiers` | `bundleIdentifiers` | Array | Target application bundle ID strings, wildcards, or group aliases. |
| `disabled` | `disabled` | Bool | When `true`, completely disables OpenClip in the target application (no popup, hotkeys ignored). |
| `hotkey-only` | `hotkeyOnly` | Bool | When `true`, suppresses automatic popup on text selection; OpenClip will only trigger when explicitly invoked via global hotkey (`⌥⌘C`). |
| `deny-paste` | `denyPaste` | Bool | Force text delivery to be a copy instead of a paste, even when the app advertises a Paste command (e.g. terminals). |
| `retrieval-mode` | `retrievalMode` | Enum | Which mechanism reads the selection. One of `ax-text-control` (default), `ax-web-area`, `browser-script`, `menu-copy`, `keyboard-copy` (see below). |
| `gate` | `gate` | Object | Pre-retrieval gate rules — `skipRoles` (AX roles never allowed to hold a selection) and `allowedCursors` (cursor classes that suggest a text context). See [`SelectionGatePolicy`](../../Sources/Core/Rules/SelectionGatePolicy.swift). |
| `use-menu-copy` | `useMenuCopy` | Bool | **Legacy alias.** `true` resolves to `retrieval-mode: "menu-copy"` (read via the AX Edit ▸ Copy menu item) only when the rule sets no `retrieval-mode` and no higher-priority builtin retrieval mode applies (the app isn't already assigned a different mode by the builtin catalog). Prefer `retrieval-mode` in new rules. |

### `retrieval-mode` values

| Value | Strategy | Target Context |
| :--- | :--- | :--- |
| `ax-text-control` | Direct AX read of `kAXSelectedTextAttribute` — zero pasteboard side-effects. Default. | Standard native text controls |
| `ax-web-area` | AX web-area read via text-marker ranges, with a settle-retry loop. | Web views and WebKit content |
| `browser-script` | Browser AppleScript bridge (`do JavaScript` / `execute javascript`); falls back to the AX web-area read on automation-permission errors. | Supported web browsers |
| `menu-copy` | AXPress the Edit ▸ Copy menu item, then archive-and-restore the pasteboard. | Terminal emulators and CLI tools |
| `keyboard-copy` | Synthesized ⌘C key event, then archive-and-restore the pasteboard. | Custom code editors and Electron apps |

These modes match the per-app defaults assigned by the builtin catalog (`DefaultAppRules.catalog`); a user rule only overrides the keys it sets, so e.g. `gate` alone leaves `retrieval-mode` at the app's default.

---

## Bundle Identifier Matching & Shortcuts

### Wildcard Pattern Matching
`RuleEngine` supports prefix wildcard matching using `.*` or global wildcard `*`:
- `"com.example.*"` matches `com.example.app1`, `com.example.app2`, etc.
- `"*"` matches all applications.

### Builtin Group Expansion Aliases

| Group Shortcut | Description |
| :--- | :--- |
| `:menu-copy-apps:` | Expands to all terminal applications configured for menu-based copy in `DefaultAppRules.menuCopyApps`. |

---

## Rule Evaluation Mechanics

1. When a selection event is detected, the trigger sites (`MacSelectionMonitor`, `HotkeyManager`) query `RuleEngine.shared.resolvePolicies(for: bundleID)`.
2. `RuleEngine` matches the target application bundle ID against effective rules (default rules + user rules, with `.*`-prefix / `*` wildcards).
3. Matched policy settings override default `AppPolicyContext` values; the resolved `retrieval-mode` and `gate` are passed to `SelectionRetrievalCoordinator` to read the selection.
4. A legacy `use-menu-copy: true` rule resolves to `retrieval-mode: "menu-copy"` only when the rule sets no explicit `retrieval-mode` and no higher-priority builtin retrieval mode applies (the app isn't already assigned a different mode by the builtin catalog).
5. If `denyPaste: true` is active for the frontmost application, paste delivery is downgraded to copy and the Paste/Cut actions are hidden from the floating popup bar (via the unified `PasteAvailability` decision).
