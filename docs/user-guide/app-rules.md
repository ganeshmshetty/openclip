# Application-Specific Policy Rules (`AppRule`)

OpenClip allows configuring application-specific behavior rules through [`AppRule`](../../Sources/Core/Rules/AppRule.swift) and [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift). App rules control how OpenClip retrieves text and delivers it (paste vs copy) when specific target macOS applications are active.

---

## JSON Configuration Format (`rules.json`)

Rules are stored in JSON configuration files (such as `~/.openclip/rules.json`) conforming to `RuleEngineConfig`:

```jsonc
{
  "rules": [
    {
      "bundle-identifiers": ["com.apple.Terminal"],
      "deny-paste": true
    },
    {
      "bundle-identifiers": ["com.example.editor"],
      "retrieval-mode": "keyboard-copy"
    },
    {
      "bundle-identifiers": ["com.example.menuapp"],
      "gate": {
        "skipRoles": [],
        "allowedCursors": ["beam", "arrow", "pointingHand", "unknown"],
        "requireSelectionBeforeCopy": false
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
| `deny-paste` | `denyPaste` | Bool | Force text delivery to be a copy instead of a paste, even when the app advertises a Paste command (e.g. terminals). |
| `retrieval-mode` | `retrievalMode` | Enum | Which mechanism reads the selection. One of `ax-text-control` (default), `ax-web-area`, `browser-script`, `menu-copy`, `keyboard-copy` (see below). |
| `gate` | `gate` | Object | Pre-retrieval gate rules — `skipRoles` (AX roles never allowed to hold a selection), `allowedCursors` (cursor classes that suggest a text context), `requireSelectionBeforeCopy` (require an existing selection before a copy-mode read). See [`SelectionGatePolicy`](../../Sources/Core/Rules/SelectionGatePolicy.swift). |
| `use-menu-copy` | `useMenuCopy` | Bool | **Legacy alias.** `true` (with no explicit `retrieval-mode`) resolves to `retrieval-mode: "menu-copy"` (read via the AX Edit ▸ Copy menu item). Prefer `retrieval-mode` in new rules. |

### `retrieval-mode` values

| Value | Strategy | Example apps |
| :--- | :--- | :--- |
| `ax-text-control` | Direct AX read of `kAXSelectedTextAttribute` — zero pasteboard side-effects. Default. | native text fields |
| `ax-web-area` | AX web-area read via text-marker ranges, with a settle-retry loop. | WebKit web content |
| `browser-script` | Browser AppleScript bridge (`do JavaScript` / `execute javascript`); falls back to the AX web-area read on automation-permission errors. | Safari, Chrome, Firefox, Arc |
| `menu-copy` | AXPress the Edit ▸ Copy menu item, then archive-and-restore the pasteboard. | Terminal, iTerm2, Ghostty |
| `keyboard-copy` | Synthesized ⌘C key event, then archive-and-restore the pasteboard. | VS Code, Zed, Obsidian, JetBrains |

These modes match the per-app defaults assigned by the builtin catalog (`DefaultAppRules.catalog`); a user rule only overrides the keys it sets, so e.g. `gate` alone leaves `retrieval-mode` at the app's default.

---

## Bundle Identifier Matching & Shortcuts

### Wildcard Pattern Matching
`RuleEngine` supports prefix wildcard matching using `.*` or global wildcard `*`:
- `"com.jetbrains.*"` matches `com.jetbrains.intellij`, `com.jetbrains.pycharm`, `com.jetbrains.goland`, etc.
- `"*" ` matches all applications.

### Builtin Group Expansion Aliases

| Group Shortcut | Expanded Application Bundle Identifiers |
| :--- | :--- |
| `:menu-copy-apps:` | `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `dev.zed.Zed`, `com.github.atom`, `com.sublimetext.*`, `notion.id`, `md.obsidian`, `com.figma.Desktop`, `net.whatsapp.WhatsApp` |

> The `:menu-copy-apps:` macro keeps expanding to the same app list for backward compatibility,
> but those apps now resolve `retrieval-mode: "keyboard-copy"` from the builtin catalog
> (`DefaultAppRules.keyboardCopyApps`), so a rule that only sets `use-menu-copy: true` against the
> macro no longer forces the AX-menu path for them. Only the terminals (`com.apple.Terminal`,
> `com.googlecode.iterm2`, `com.mitchellh.ghostty`) default to `menu-copy`.

---

## Rule Evaluation Mechanics

1. When a selection event is detected, the trigger sites (`MacSelectionMonitor`, `HotkeyManager`) query `RuleEngine.shared.resolvePolicies(for: bundleID)`.
2. `RuleEngine` matches the target application bundle ID against effective rules (default rules + user rules, with `.*`-prefix / `*` wildcards).
3. Matched policy settings override default `AppPolicyContext` values; the resolved `retrieval-mode` and `gate` are passed to `SelectionRetrievalCoordinator` to read the selection.
4. A legacy `use-menu-copy: true` rule with no explicit `retrieval-mode` resolves to `retrieval-mode: "menu-copy"` (only when the app isn't already assigned a different mode by the builtin catalog).
5. If `denyPaste: true` is active for the frontmost application, paste delivery is downgraded to copy and the Paste/Cut actions are hidden from the floating popup bar (via the unified `PasteAvailability` decision).
