# Application-Specific Policy Rules (`AppRule`)

OpenClip allows configuring application-specific behavior rules through [`AppRule`](../../Sources/Core/Rules/AppRule.swift) and [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift). App rules control how OpenClip detects selections, retrieves text, and enables or suppresses formatting actions when specific target macOS applications are active.

---

## JSON Configuration Format (`rules.json`)

Rules are stored in JSON configuration files (such as `~/.openclip/rules.json`) conforming to `RuleEngineConfig`:

```json
{
 "rules": [
 {
 "bundle-identifiers": [
 "com.jetbrains.*",
 "com.apple.Terminal",
 "com.sublimetext.*"
 ],
 "deny-formatting": true
 },
 {
 "bundle-identifiers": [
 "md.obsidian",
 "com.skype.skype",
 "com.evernote.Evernote"
 ],
 "grab-pb": true
 },
 {
 "bundle-identifiers": [
 ":chromium-group:"
 ],
 "assume-paste": true
 }
 ]
}
```

---

## Policy Properties Reference

| Property Key in JSON | Code Identifier | Type | Description |
| :--- | :--- | :--- | :--- |
| `bundle-identifiers` | `bundleIdentifiers` | Array | Target application bundle ID strings, wildcards, or group aliases. |
| `deny-formatting` | `denyFormatting` | Bool | When `true`, suppresses text case transformations (e.g. UPPERCASE) in IDEs/Terminals. |
| `grab-pb` | `grabPasteboard` | Bool | When `true`, opts into using `Cmd+C` pasteboard copy fallback for apps without AX selection support. |
| `assume-paste` | `assumePaste` | Bool | Assumes text replacement should be performed via paste event simulation. |
| `deny-probe` | `denyProbe` | Bool | Prevents active AX element probing. |
| `deny-preprobe` | `denyPreprobe` | Bool | Prevents background AX pre-probing. |

---

## Bundle Identifier Matching & Shortcuts

### Wildcard Pattern Matching
`RuleEngine` supports prefix wildcard matching using `.*` or global wildcard `*`:
- `"com.jetbrains.*"` matches `com.jetbrains.intellij`, `com.jetbrains.pycharm`, `com.jetbrains.goland`, etc.
- `"*" ` matches all applications.

### Builtin Group Expansion Aliases

| Group Shortcut | Expanded Application Bundle Identifiers |
| :--- | :--- |
| `:safari-group:` | `com.apple.Safari`, `com.apple.SafariTechnologyPreview` |
| `:chromium-group:` | `com.google.Chrome`, `com.brave.Browser`, `com.microsoft.edgemac` |
| `:firefox-group:` | `org.mozilla.firefox` |
| `:arc-group:` | `company.thebrowser.Browser` |

---

## Rule Evaluation Mechanics

1. When text selection is detected, `ActionCoordinator` queries `RuleEngine.shared.resolvePolicies(for: bundleID)`.
2. `RuleEngine` matches the target application bundle ID against effective rules (default rules + user rules).
3. Matched policy settings override default `AppPolicyContext` values.
4. If `denyFormatting: true` is active for the frontmost application, transform actions are automatically hidden from the floating popup bar.
