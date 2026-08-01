# Single-File Text Snippets

In addition to multi-file `.openclipext` packages, OpenClip supports lightweight **single-file text snippets**. Snippets allow developers and power users to create actions inside a single text file using header comments (`#openclip` or `//openclip`).

---

## Snippet Format Structure

A snippet file starts with a header block declaring metadata key-value pairs followed by inline script code or URL template definitions:

```
#openclip
title: My Quick Action
icon: sparkles
identifier: com.example.quickaction
...
```

---

## Key-Value Header Reference

| Key | Description | Example |
|-----|-------------|---------|
| `title` (or `name`) | Action display title in HUD | `title: Uppercase JS` |
| `icon` | Icon name or SF Symbol | `icon: character.uppercase` |
| `identifier` | Unique identifier string | `identifier: snippet.uppercase` |
| `url` | URL template (for URL actions) | `url: https://google.com/search?q={text}` |
| `javascript` (or `js`) | Inline JavaScript code string | `javascript: selection.toUpperCase()` |
| `applescript` | Inline AppleScript command | `applescript: display dialog selection` |
| `shell script` (or `sh`) | Inline Shell script code | `sh: echo "$POPCLIP_TEXT" | tr '[:lower:]' '[:upper:]'` |

---

## Examples

### Example 1: JavaScript Snippet (`.js` / `.txt`)

```javascript
//openclip
// title: Reverse Text
// icon: arrow.triangle.2.circlepath
// identifier: snippet.reverse
// js: selection.split('').reverse().join('')
```

### Example 2: AppleScript Snippet (`.applescript`)

```applescript
#openclip
# title: Speak Selection
# icon: speaker.wave.2
# applescript: say OPENCLIP_TEXT
```

### Example 3: Zsh Shell Snippet (`.sh`)

```bash
#!/bin/zsh
#openclip
# title: MD Code Block
# icon: curlybraces
# sh: printf "```\n%s\n```" "$POPCLIP_TEXT"
```

### Example 4: URL Template Snippet (`.txt`)

```
#openclip
title: Search GitHub
icon: magnify
url: https://github.com/search?q={text}
```

---

## How OpenClip Parses Snippets

The `OpenClipSnippetParser` inspects the top lines of any imported file:

1. Looks for `#openclip`, `//openclip`, or `#popclip` magic headers.
2. Extracts key-value pairs (`title:`, `icon:`, `url:`, `js:`, `applescript:`, `sh:`).
3. Instantiates the corresponding Swift action object (`CustomAction`, `ScriptAction`, or `URLTemplateAction`).
4. Registers the action instantly into `ActionRegistry`.
