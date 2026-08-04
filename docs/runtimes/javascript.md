# JavaScript Action Runtime

The JavaScript action runtime ([`OpenClipJSHost`](../../Sources/OpenClip/Actions/OpenClipJSHost.swift),
reached via [`JavaScriptAction`](../../Sources/OpenClip/Actions/JavaScriptAction.swift)) executes
`type: "javascript"` extension scripts using macOS `JSContext` (JavaScriptCore). It injects a
read-only `openclip` object into the global scope and resolves collected effects into an
[`ActionResult`](../../Sources/Core/Actions/ActionResult.swift).

## The `openclip` JS Object

```typescript
interface OpenClipBridge {
  input: {
    text: string;            // Full selected text
    matchedText: string;     // Text matched by the action's regex (falls back to text)
    captures: string[];      // Regex capture groups (empty when no regex)
    app: { bundleID: string; name: string }; // Frontmost source app
  };
  options: Record<string, string>; // Resolved option values (values only, read-only)
  option(id: string): string | undefined; // Functional form of options[id]

  // Effect functions (call order is preserved):
  paste(value: string): void;
  copy(value: string): void;
  cut(value: string): void;
  openURL(urlString: string): void;      // Invalid URLs are ignored
  keyPress(key: string, modifiers: string[]): void; // e.g. openclip.keyPress("a", ["command"])
  runShortcut(name: string): void;       // Runs a macOS Shortcut (requires /usr/bin/shortcuts)
  notify(title: string, body: string): void;
  showStatus(message: string, style?: string): void; // style: "success" | "error" | "info"
  showBubble(payload: object): void;     // See below
  keepVisible(): void;                   // Keep the popup open after the result
  requireConfiguration(payload: object): void; // { reason?: string, missing?: string[] }
}
```

Modifier names accepted by `keyPress`: `command`/`cmd`, `shift`, `option`/`alt`,
`control`/`ctrl`. The key is a macOS virtual-key name (QWERTY/ANSI layout is assumed), e.g.
letters `a`–`z`, digits `0`–`9`, or named keys like `return`, `space`, `escape`.

`showBubble` accepts an object with optional `title`, `icon`, `subtitle`, `body`, `emphasis`
(`"info"` | `"menu"` | default `"result"`), `rows` (`[{type:"text", value}]`), and `footer`
(`"paste"`/`"copy"` presets or `{title, icon, action: "paste"|"copy", value}` objects).

## Options & Preference Integration

Extension options declared in the manifest are resolved through the injected option store
(`ActionOptionReading`) — **not** `UserDefaults` directly. Non-secret options come from
`SettingsStore` (`SettingKey<String>("action.<id>.option.<identifier>")`); `.secret` options come
from the Keychain via `KeychainActionOptionStore`. Values land in `openclip.options` and
`openclip.option(id)`. The wrapped script also receives them as the second argument:

```javascript
(function() {
  var selection = openclip.input.text;
  var options = openclip.options;
  // ...your code...
  if (typeof action === 'function') { return action(selection, options); }
  if (typeof main === 'function')   { return main(selection, options); }
  return null;
})();
```

Define an `action(selection, options)` or `main(selection, options)` entry function.

## Result Resolution

`OpenClipJSHost.run` resolves the outcome in a deterministic order:

1. `requireConfiguration(...)` → `.openConfiguration`.
2. `showBubble(...)` → `.showBubble`.
3. `showStatus(...)` (with no effects) → `.showStatus`.
4. Effects (paste/copy/cut/openURL/keyPress/runShortcut/notify) → single `.paste`/`.copy`/etc, or
   `.sequence` of them when multiple were called.
5. String return value → `.copy(string)`.
6. Otherwise → `.success`.

If `keepVisible()` was called, the resolved result is wrapped in `.keepVisible(...)`.
A JavaScript exception produces `.showStatus(.error, message)` instead of throwing; the popup
stays visible.

## Practical Examples

### Prettify JSON (returns a string → copied)

```javascript
function action(selection) {
  try {
    var obj = JSON.parse(selection);
    var indent = parseInt(openclip.options.indent_spaces || "2", 10);
    return JSON.stringify(obj, null, indent);
  } catch (e) {
    return "Invalid JSON: " + e.message;
  }
}
```

### Search Web (opens a URL)

```javascript
function action(selection) {
  var query = encodeURIComponent(selection.trim());
  openclip.openURL("https://duckduckgo.com/?q=" + query);
}
```

### Replace the selection with uppercased text

```javascript
function action(selection) {
  openclip.paste(selection.toUpperCase());
}
```
