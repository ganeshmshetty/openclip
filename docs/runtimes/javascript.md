# JavaScript Action Runtime

The JavaScript action runtime ([`JavaScriptAction`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Actions/JavaScriptAction.swift)) executes JavaScript code using macOS `JSContext` (JavaScriptCore framework). It provides an in-memory JS execution environment with access to a bridge object named `openclip`.

---

## The `openclip` JS Bridge Object

OpenClip injects the `openclip` object into the global execution context before running the script:

```typescript
interface OpenClipBridge {
 input: {
 text: string; // Current selected text
 };
 options: Record<string, string>; // Key-value dictionary of extension options

 // Side-effect functions:
 openUrl(url: string): void;
 openURL(url: string): void;
 pasteText(text: string): void;
}
```

---

## Options & Preference Integration

Extension options defined in `manifest.json` are loaded dynamically via [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift) using strongly-typed setting keys:

```swift
for opt in actionOptions {
 let key = "action.\(id).option.\(opt.identifier)"
 optionsDict[opt.identifier] = settingsStore.get(SettingKey<String>(key, defaultValue: opt.defaultValue ?? ""))
}
```

- Direct calls to `UserDefaults.standard` are **never** used.
- Options configured by users in the Preferences window are automatically passed into `openclip.options`.

---

## Script Execution Flow & Entry Points

`JavaScriptAction` wraps user code in an IIFE and evaluates standard entry point functions (`action` or `main`):

```javascript
(function() {
 var selection = openclip.input.text;
 var options = openclip.options;

 // User script code body
 // ...

 if (typeof action === 'function') {
 return action(selection, options);
 }
 if (typeof main === 'function') {
 return main(selection, options);
 }
 return null;
})();
```

---

## Side-Effect Handling & Result Resolution

The runtime resolves the execution outcome into an [`ActionResult`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionResult.swift) based on function calls or return values:

1. **`openclip.openUrl(urlString)`**:
 - If invoked, execution returns `ActionResult.openURL(URL)`.
2. **`openclip.pasteText(textString)`**:
 - If invoked, execution returns `ActionResult.paste(String)` (replaces selection or pastes into frontmost app).
3. **Return Value (String)**:
 - If the function returns a non-null string, execution returns `ActionResult.copy(String)`.
4. **Void / Undefined Return**:
 - Execution returns `ActionResult.success`.

---

## Practical Examples

### Prettify JSON Snippet

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

### Search Web & Open URL

```javascript
function action(selection) {
 var query = encodeURIComponent(selection.trim());
 openclip.openUrl("https://duckduckgo.com/?q=" + query);
}
```
