# URL Templates Engine

The URL templates engine ([`URLTemplateAction`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/URLTemplateAction.swift)) powers instant web search, documentation lookup, and custom URI scheme deep-linking actions.

---

## Execution Mechanism

When a user selects a URL template action:

1. **Text Extraction**: Selected text is trimmed of leading and trailing whitespace.
2. **Placeholder Substitution**: [`TextPlaceholderEngine`](file:///Users/ganesh/dev/openclip/Sources/Core/Utils/TextPlaceholderEngine.swift) substitutes template tokens with percent-encoded query parameters.
3. **URL Resolution**: The resulting string is parsed into a `URL` object and returned as `ActionResult.openURL(url)`.
4. **Platform Launch**: `DefaultActionResultHandler` opens the URL via `NSWorkspace.shared.open(url)`.

---

## Supported Placeholders

[`TextPlaceholderEngine`](file:///Users/ganesh/dev/openclip/Sources/Core/Utils/TextPlaceholderEngine.swift) replaces the following template tokens:

| Placeholder Token | Replacement Value | Encoding |
| :--- | :--- | :--- |
| `{query}` | Selected text string | Percent-encoded (`.urlQueryAllowed`) |
| `{text}` | Selected text string | Percent-encoded (`.urlQueryAllowed`) |

---

## Regex Pattern Gating (`regexPattern`)

URL template actions accept an optional `regexPattern` field. When provided, the action is enabled only when the selected text matches the regular expression pattern.

```swift
public func isEnabled(for context: ActionContext) -> Bool {
 let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
 guard !text.isEmpty else { return false }

 if let pattern = regexPattern, !pattern.isEmpty {
 do {
 let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
 let range = NSRange(text.startIndex..., in: text)
 return regex.firstMatch(in: text, options: [], range: range) != nil
 } catch {
 return true
 }
 }
 return true
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
