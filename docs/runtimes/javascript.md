# JavaScript Extension Runtime (JSC)

OpenClip utilizes the native macOS **JavaScriptCore (JSC)** framework (`JavaScriptAction.swift`) to execute JavaScript extensions in a lightweight, isolated execution environment.

---

## Global Bridge Object (`openclip`)

OpenClip injects a native bridge object named `openclip` into the global JS context prior to script execution:

```javascript
// Properties provided by openclip bridge
openclip.input.text          // Selected text string
openclip.options             // Dictionary of user-configured extension options

// Helper functions provided by openclip bridge
openclip.pasteText(string)   // Replaces active text selection with new string
openclip.copy(string)        // Copies string to macOS Clipboard
openclip.openUrl(urlString)  // Opens URL in default browser
```

---

## Entry Point Functions

OpenClip automatically detects and executes any of the following entry points in your script:

1. `action(selection, options)`: Recommended entry point function. Return a string to copy to clipboard, or call bridge methods.
2. `main(selection, options)`: Alternative entry point function.
3. Top-level expression output: If no `action` or `main` function is defined, OpenClip uses the string evaluation result of the script.

---

## Copy-Pasteable JavaScript Examples

### Example 1: JSON Formatter & Prettifier

Formats raw JSON text with 2-space indentation.

```json
// openclip.json
{
  "Identifier": "com.openclip.jsonprettify",
  "Name": "JSON Prettifier",
  "Actions": [
    {
      "Title": "Prettify JSON",
      "Icon": "symbol:curlybraces",
      "Script": "main.js"
    }
  ]
}
```

```javascript
// main.js
function action(selection, options) {
    try {
        const parsed = JSON.parse(selection);
        const formatted = JSON.stringify(parsed, null, 2);
        // Replace selection with formatted JSON
        openclip.pasteText(formatted);
    } catch (err) {
        // Output error to clipboard if invalid JSON
        openclip.copy("Invalid JSON: " + err.message);
    }
}
```

---

### Example 2: Word Count & Reading Time Estimator

Calculates character count, word count, line count, and estimated reading time.

```json
// openclip.json
{
  "Identifier": "com.openclip.wordcount",
  "Name": "Word Count Stats",
  "Actions": [
    {
      "Title": "Word Stats",
      "Icon": "symbol:chart.bar.doc.horizontal",
      "Script": "main.js"
    }
  ]
}
```

```javascript
// main.js
function action(selection, options) {
    const chars = selection.length;
    const words = selection.trim().split(/\s+/).filter(Boolean).length;
    const lines = selection.split(/\r\n|\r|\n/).length;
    const readingTimeMinutes = Math.ceil(words / 200);

    const stats = `📊 Stats:\n- Characters: ${chars}\n- Words: ${words}\n- Lines: ${lines}\n- Est. Read Time: ~${readingTimeMinutes} min`;
    
    openclip.copy(stats);
}
```

---

### Example 3: Text Transformer with Declarative Options

Converts text casing based on a dropdown option selected in OpenClip Preferences.

```json
// openclip.json
{
  "Identifier": "com.openclip.casemodifier",
  "Name": "Case Modifier",
  "Actions": [
    {
      "Title": "Modify Case",
      "Icon": "symbol:textformat",
      "Script": "main.js"
    }
  ],
  "Options": [
    {
      "identifier": "target_case",
      "label": "Target Case Style",
      "type": "multiple",
      "default value": "camelCase",
      "options": ["camelCase", "snake_case", "kebab-case", "UPPERCASE", "lowercase"]
    }
  ]
}
```

```javascript
// main.js
function action(selection, options) {
    const targetCase = options.target_case || "camelCase";
    let result = selection;

    const words = selection.trim().split(/[\s_\-]+/).filter(Boolean);

    switch (targetCase) {
        case "camelCase":
            result = words.map((w, i) => i === 0 ? w.toLowerCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('');
            break;
        case "snake_case":
            result = words.map(w => w.toLowerCase()).join('_');
            break;
        case "kebab-case":
            result = words.map(w => w.toLowerCase()).join('-');
            break;
        case "UPPERCASE":
            result = selection.toUpperCase();
            break;
        case "lowercase":
            result = selection.toLowerCase();
            break;
    }

    openclip.pasteText(result);
}
```
