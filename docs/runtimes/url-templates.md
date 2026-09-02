# URL Templates Engine

The URL templates engine ([`URLTemplateAction`](../../Sources/Core/Actions/URLTemplateAction.swift)) powers instant web search, documentation lookup, and custom URI scheme deep-linking actions.

---

## Execution Mechanism

When a user selects a URL template action:

1. **Text Extraction**: Selected text is trimmed of leading and trailing whitespace.
2. **Placeholder Substitution**: [`TextPlaceholderEngine`](../../Sources/Core/Utils/TextPlaceholderEngine.swift) substitutes template tokens with percent-encoded query parameters.
3. **URL Resolution**: The resulting string is parsed into a `URL` object and returned as `ActionResult.openURL(url)`.
4. **Platform Launch**: `DefaultActionResultHandler` opens the URL via `NSWorkspace.shared.open(url)`.

---

## Supported Placeholders

[`TextPlaceholderEngine`](../../Sources/Core/Utils/TextPlaceholderEngine.swift) replaces the following template tokens:

| Placeholder Token | Replacement Value | Encoding |
| :--- | :--- | :--- |
| `{query}`, `{text}` | Selected text string | Percent-encoded (`Constants.queryValueAllowed`) |
| `{matched}` | Substring matched by regex (full text if no regex) | Percent-encoded (`Constants.queryValueAllowed`) |
| `{capture1}`…`{captureN}` / `{1}`…`{N}` | Regex capture groups | Percent-encoded (`Constants.queryValueAllowed`) |
| `{bundleID}` | Source application bundle identifier | Percent-encoded (`Constants.queryValueAllowed`) |
| `{html}`, `{rtf}` | HTML/RTF selection content if present | Percent-encoded (`Constants.queryValueAllowed`) |

---

## Regex Pattern Gating & Visibility Rules

URL template actions support regex gating (via `regexPattern` or `ExtensionActionRules`). When evaluated, enablement and capture extraction delegate to [`ActionVisibility`](../../Sources/Core/Actions/ActionVisibility.swift):

```swift
@MainActor
public func isEnabled(for context: ActionContext) -> Bool {
    guard let rules else {
        return ActionVisibility.isEnabled(
            requirements: nil,
            legacyRegex: regexPattern,
            context: context
        ).enabled
    }
    return rules.resolveVisibility(for: context).enabled
}
```

### Common Regex Examples

- **Match URLs Only**: `^https?://\\S+$`
- **Match Issue Tracker Numbers**: `^#[0-9]+$` or `^[A-Z]+-[0-9]+$`
- **Match IP Addresses**: `^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$`

---

## Practical Examples

```json
{
 "id": "builtin.search.google",
 "title": "Search Google",
 "icon": "symbol:magnifyingglass",
 "url": "https://www.google.com/search?q={query}"
}
```

```json
{
 "id": "action.github.repo",
 "title": "Open GitHub Repo",
 "icon": "symbol:book",
 "url": "https://github.com/{query}",
 "regex": "^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$"
}
```
