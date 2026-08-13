# Application-Specific Policy Rules (`AppRule`)

OpenClip allows configuring application-specific behavior rules through [`AppRule`](../../Sources/Core/Rules/AppRule.swift) and [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift). App rules control how OpenClip retrieves text and delivers it (paste vs copy) when specific target macOS applications are active.

---

## JSON Configuration Format (`rules.json`)

Rules are stored in JSON configuration files (such as `~/.openclip/rules.json`) conforming to `RuleEngineConfig`:

```json
{
 "rules": [
 {
 "bundle-identifiers": [
 "com.apple.Terminal"
 ],
 "deny-paste": true
 },
 {
 "bundle-identifiers": [
 ":menu-copy-apps:"
 ],
 "use-menu-copy": true
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
| `use-menu-copy` | `useMenuCopy` | Bool | Read the selection via the AX Edit ▸ Copy menu item instead of a Cmd+C key event (Electron/JS apps). |

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

---

## Rule Evaluation Mechanics

1. When text selection is detected, `ActionCoordinator` queries `RuleEngine.shared.resolvePolicies(for: bundleID)`.
2. `RuleEngine` matches the target application bundle ID against effective rules (default rules + user rules).
3. Matched policy settings override default `AppPolicyContext` values.
4. If `denyPaste: true` is active for the frontmost application, paste delivery is downgraded to copy and the Paste/Cut actions are hidden from the floating popup bar (via the unified `PasteAvailability` decision).
