# URL Template Extension Runtime

URL Template extensions (`URLTemplateAction.swift`) provide a zero-code way to build web search lookups, dictionary queries, API links, and deep app URLs.

---

## Template Placeholders

URL templates replace dynamic placeholders with percent-encoded text selection values:

- `{text}`: The highlighted text string (percent-encoded for URL query parameters).
- `{query}`: Alias for `{text}`.

---

## Contextual Regular Expression Filtering

URL extensions can declare a `regexPattern` (or `Regular Expression` key in `openclip.json`). OpenClip will **only** display the action button in the HUD if the highlighted text matches the specified regex!

---

## Copy-Pasteable URL Template Examples

### Example 1: Multi-Search Engine Bundle

Search Google, DuckDuckGo, or WolframAlpha.

```json
// openclip.json
{
  "Identifier": "com.openclip.websearches",
  "Name": "Web Search Pack",
  "Actions": [
    {
      "Title": "DuckDuckGo",
      "Icon": "symbol:magnifyingglass",
      "URL": "https://duckduckgo.com/?q={text}"
    },
    {
      "Title": "WolframAlpha",
      "Icon": "symbol:function",
      "URL": "https://www.wolframalpha.com/input/?i={text}"
    }
  ]
}
```

---

### Example 2: Jira Ticket Direct Opener (Contextual Regex)

Only appears when highlighting Jira ticket keys like `PROJ-1234` or `DEV-890`.

```json
// openclip.json
{
  "Identifier": "com.openclip.jiralookup",
  "Name": "Open Jira Ticket",
  "Actions": [
    {
      "Title": "Open Jira",
      "Icon": "symbol:ticket",
      "URL": "https://mycompany.atlassian.net/browse/{text}",
      "Regular Expression": "^[A-Z]{2,10}-\\d+$"
    }
  ]
}
```

---

### Example 3: GitHub Code & Repository Search

Search GitHub code repositories for highlighted functions or terms.

```json
// openclip.json
{
  "Identifier": "com.openclip.githubsearch",
  "Name": "GitHub Search",
  "Actions": [
    {
      "Title": "GitHub Code",
      "Icon": "symbol:chevron.left.forwardslash.chevron.right",
      "URL": "https://github.com/search?q={text}&type=code"
    }
  ]
}
```

---

### Example 4: Google Maps Coordinates Lookup

Appears when highlighting latitude and longitude coordinates (e.g. `37.7749, -122.4194`).

```json
// openclip.json
{
  "Identifier": "com.openclip.mapslookup",
  "Name": "Open Coordinates in Maps",
  "Actions": [
    {
      "Title": "Open in Maps",
      "Icon": "symbol:map",
      "URL": "https://maps.apple.com/?q={text}",
      "Regular Expression": "^-?\\d+(\\.\\d+)?,\\s*-?\\d+(\\.\\d+)?$"
    }
  ]
}
```
