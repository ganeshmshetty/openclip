# Standalone Script Snippets (`OpenClipSnippetParser`)

In addition to `.openclipext` package directories, OpenClip supports **standalone single-file script snippets** (`.js`, `.applescript`, `.sh`, `.py`). Standalone scripts declare action metadata in header comment blocks that are extracted by [`OpenClipSnippetParser`](../../Sources/Core/Extensions/OpenClipSnippetParser.swift).

---

## Parser Architecture & Design Constraints

- **Text Parser**: `OpenClipSnippetParser` operates purely on string content and line scanning.
- **Zero UI Dependencies**: Free of AppKit and SwiftUI.
- **Current limitation**: The parser is annotated `@MainActor`, which forces main-actor hops during extension directory scanning. Removing the annotation is planned but not done; treat it as a pure string parser conceptually.

---

## Header Syntax & Format

Header metadata can be specified using single-line comment prefixes (`//` or `#`) or block keys.

### Example 1: Standalone JavaScript Snippet (`upper.js`)

```javascript
// title: Upper Case Transformer
// icon: symbol:textformat.characters
// identifier: com.user.snippet.uppercase
// javascript:
var text = openclip.input.text;
openclip.paste(text.toUpperCase());
```

### Example 2: Standalone Shell Script (`format-sql.sh`)

```bash
#!/bin/bash
# title: Format SQL Query
# icon: symbol:server.rack
# identifier: com.user.snippet.sqlformat
# shell script:
python3 -c "import sqlparse, sys; print(sqlparse.format(sys.stdin.read(), reindent=True))"
```

### Example 3: Standalone AppleScript Snippet (`create-note.applescript`)

```applescript
-- title: New Quick Note
-- icon: symbol:note.text
-- identifier: com.user.snippet.newnote
-- applescript:
tell application "Notes"
 make new note at folder "Notes" with data OPENCLIP_TEXT
end tell
```

### Example 4: Standalone URL Search Snippet (`search-mdn.sh`)

```bash
# title: Search MDN
# icon: symbol:doc.text.magnifyingglass
# url: https://developer.mozilla.org/en-US/search?q={query}
```

---

## Header Keys Matrix

The parser extracts key-value metadata matching the following recognized keys:

| Header Key | Recognized Aliases | Description |
| :--- | :--- | :--- |
| **Title** | `title`, `name` | User-facing display title in popup panel and preferences. |
| **Icon** | `icon` | Icon specifier (`symbol:name`, `icon.png`, or SF Symbol string). |
| **Identifier** | `identifier`, `id` | Unique action identifier string (defaults to `snippet.<slug>`). |
| **URL Action** | `url` | URL template string containing `{query}` or `{text}` placeholders. |
| **JavaScript** | `javascript`, `js` | Inline code block or multiline code following the key. |
| **AppleScript** | `applescript` | Inline AppleScript automation snippet block. |
| **Shell Script** | `shell script`, `sh`, `shell` | Inline Zsh/Bash/Python executable script block. |

---

## Parsing Algorithm Details

1. **Header Line Scanning**: Scans up to `Constants.maxHeaderLinesToScan` lines for header comment prefixes (`//`, `#`, `//openclip`, `#openclip`).
2. **Key-Value Splitting**: Splits line on the first colon (`:`).
3. **Multiline Body Mode**: When a runtime key (`url`, `javascript`, `applescript`, `shell script`) is encountered without inline content, subsequent lines are accumulated as the script body string. Body mode only ends when a `#`-prefixed recognized header key appears (e.g. a later `# Icon:` line); `//`-prefixed lines and everything else stay part of the body — this preserves JS comments and URLs containing `#` fragments.
4. **Action Instantiation**: The parsed tuple `(ExtensionMetadata, ExtensionActionMetadata)` is passed to `DefaultActionFactory` to instantiate the runtime action.
