# JavaScript Action Runtime

The JavaScript action runtime ([`OpenClipJSHost`](../../Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift),
reached via [`JavaScriptAction`](../../Sources/OpenClip/Platform/Runtimes/JavaScriptAction.swift)) executes
`type: "javascript"` extension scripts using macOS `JSContext` (JavaScriptCore). It injects a
read-only `openclip` object into the global scope and resolves collected effects into an
[`ActionResult`](../../Sources/Core/Actions/ActionResult.swift).

Extensions opt into **asynchronous** execution with the manifest flag `"async": true`
(`ExtensionActionMetadata.isAsync`). Async extensions get a `fetch()` polyfill bridged to URLSession,
and the host awaits the action's returned promise (or the promise an entry function returns) before
resolving. Without the flag, scripts run in the legacy synchronous mode described below and any
promise-like return is ignored (never pasted as `[object Promise]`).

## Console logging

A global `console.log(...)` is available in every script (sync and async). It is variadic — e.g.
`console.log('x', 42, { a: 1 })` — and redacts values into non-sensitive structural metadata (e.g.
`<string len=1>`, `<number>`, `<Object keys=[a]>`) before producing a single log line.
To adhere to OpenClip's privacy guidelines ("keep text, clipboard, and extension data private"), raw string
contents and object property values are never logged verbatim.
It routes to the app's `js` log category (`Log.js`), so it is a debugging aid rather than a runtime
failure: without the shim, `console` was undefined and calling `console.log` threw a `ReferenceError`
that broke the action. Filter it with `log stream --predicate 'subsystem == "com.openclip" && category == "js"'`.

## The `openclip` JS Object

```typescript
interface OpenClipBridge {
  input: {
    text: string;            // Full selected text
    html: string;            // Source-app HTML (when available, else empty)
    rtf: string;             // Source-app RTF (when available, else empty)
    matchedText: string;     // Text matched by the action's regex (falls back to text)
    captures: string[];      // Regex capture groups (empty when no regex)
    app: { bundleID: string; name: string }; // Frontmost source app
    isSecondaryClick: boolean; // True on a right-click or ⇧-click activation
  };
  options: Record<string, string>; // Resolved option values (values only, read-only)
  option(id: string): string | undefined; // Functional form of options[id]
  locale: string;          // User's active locale identifier (e.g. "zh_CN", "en_US")
  language: string;        // Active language/script tag (e.g. "zh-Hans", "en")
  i18n(dict: Record<string, string>): string; // Resolves dictionary against active language with fallbacks
  pasteboard: {
    text: string;          // Plain text content (getter/setter emits openclip.copy)
    html: string;          // HTML content (getter/setter emits openclip.copyContent({ html }))
    rtf: string;           // RTF content (getter/setter emits openclip.copyContent({ rtf }))
    content: Record<string, string>; // Multi-flavor content (getter/setter emits copyContent)
    hasContent: boolean;   // True if non-empty, non-concealed content exists
    hasHtml: boolean;      // True if HTML flavor is available
    hasRtf: boolean;       // True if RTF flavor is available
    types: string[];       // UTI types on the pasteboard
  };

  // Effect functions (call order is preserved):
  paste(value: string): void;
  copy(value: string): void;
  pasteContent(payload: { 'public.utf8-plain-text'?: string; 'public.html'?: string; 'public.rtf'?: string } | { text?: string; html?: string; rtf?: string }): void;
  copyContent(payload: { 'public.utf8-plain-text'?: string; 'public.html'?: string; 'public.rtf'?: string } | { text?: string; html?: string; rtf?: string }): void;
  cut(value: string): void;
  openURL(urlString: string): void;      // Invalid URLs are ignored
  keyPress(key: string, modifiers: string[]): void; // e.g. openclip.keyPress("a", ["command"])
  runShortcut(name: string): void;       // Runs a macOS Shortcut (requires /usr/bin/shortcuts)
  notify(title: string, body: string): void;
  toast(message: string, style?: string, options?: { keepVisible?: boolean }): void; // style: "success" | "error" | "info"
  requireConfiguration(payload: object): void; // { reason?: string, missing?: string[] }
}
```

Modifier names accepted by `keyPress`: `command`/`cmd`, `shift`, `option`/`alt`,
`control`/`ctrl`. The key is a macOS virtual-key name (QWERTY/ANSI layout is assumed), e.g.
letters `a`–`z`, digits `0`–`9`, or named keys like `return`, `space`, `escape`.

The former canvas bridge (`showContent(tree, { size })` / `h()`) has been **removed**; calling
those names surfaces a JS error (`.toast(.error)`).

## Options & Preference Integration

Extension options declared in the manifest are resolved through the injected option store
(`ActionOptionReading`) — **not** `UserDefaults` directly. Non-secret options come from
`SettingsStore` (`SettingKey<String>("action.<id>.option.<identifier>")`); `.secret` options come
from `SecretStore` (`~/.openclip/secrets.json` with POSIX 0600 permissions) via `SecretActionOptionStore`. Values land in `openclip.options` and
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

## Secondary click behavior (`isSecondaryClick`)

A right-click or ⇧-click activation surfaces as `openclip.input.isSecondaryClick === true`. JS
actions **cannot** declare a manifest `secondary` (rejected at validation), so a distinct secondary
behavior is authored **imperatively**: branch on the flag and emit an explicit effect for each path —
`openclip.paste(...)` for the primary, `openclip.copy(...)` for the secondary — rather than relying
on a string-return convention.

```javascript
function action(selection) {
  const result = selection.toUpperCase();
  if (openclip.input.isSecondaryClick) {
    openclip.copy(result);   // secondary click → copy
  } else {
    openclip.paste(result);  // primary click → paste
  }
}
```

The effect the branch picks becomes the action's primary result, so the standard delivery pipeline
still applies to it (the paste→copy probe, and the click's declared `toast`/`secondaryToast`, see
[`Extensions/AGENTS.md` §5b/§5c](../../Extensions/AGENTS.md)).

## Pasteboard API (`openclip.pasteboard`)

`openclip.pasteboard` provides a snapshot of the current system pasteboard at the time the action runs, with reactive getters and setters:

- `openclip.pasteboard.text`: Getter returns plain text string. Setting it (`openclip.pasteboard.text = "..."`) triggers an `openclip.copy(...)` effect.
- `openclip.pasteboard.html`: Getter returns HTML string. Setting it triggers `openclip.copyContent({ html: "..." })`.
- `openclip.pasteboard.rtf`: Getter returns RTF string. Setting it triggers `openclip.copyContent({ rtf: "..." })`.
- `openclip.pasteboard.content`: Getter returns a dictionary of available types and their representations. Setting it triggers `openclip.copyContent(...)`.
- `openclip.pasteboard.hasContent`: Boolean indicating whether non-empty, non-concealed clipboard content is present.
- `openclip.pasteboard.hasHtml` / `openclip.pasteboard.hasRtf`: Booleans indicating whether HTML or RTF flavors exist.
- `openclip.pasteboard.types`: String array of available UTI types (e.g. `["public.utf8-plain-text", "public.html"]`).

*Privacy Guard*: If the clipboard contains concealed types from password managers (e.g. `org.nspasteboard.ConcealedType`, `com.agilebits.onepassword`), `hasContent` returns `false` and text/html/rtf values are redacted to empty strings.

## Async Mode (`"async": true`)

In async mode the entry function may return a `Promise`. The wrapped script dispatches the entry
point through an internal `__openclip_dispatch` that settles the host's promise bridge — immediately
for synchronous returns, via `.then`/catch for promises. A script with no `action`/`main` entry
(top-level side effects only) still settles, so it never hangs. A rejected promise surfaces as
`.toast(.error, message)`.

### `fetch(url, options)`

Async scripts get a global `fetch(url, options)` polyfill bridged to URLSession:

```javascript
async function action(selection) {
  const r = await openclip.fetch("https://example.com/api", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ q: selection })
  });
  const body = await r.json();
  return r.status + ":" + body.ok; // "201:true"
}
```

`options`: `method` (default GET), `headers` (object), `body` (string; use `JSON.stringify` for
JSON). The response is `{ status: number, ok: boolean, text(): Promise<string>,
json(): Promise<any> }`. Network errors reject the promise. Requests use the injected URLSession
(`URLSession.shared` in production; tests inject a URLProtocol-mocked ephemeral session).

### Execution model & watchdog

Every run executes inside a `Task.detached` on a background thread — never the `MainActor`. All
JavaScript VM access is confined to that single thread; URLSession completions hop back onto the
thread's CFRunLoop via `CFRunLoopPerformBlock` + `CFRunLoopWakeUp`, and the host pumps the runloop
until the promise settles. A watchdog (`TimeoutFlag`, mirroring the `ShellProcessRunner` pattern)
throws `Script timed out after N seconds` after `Constants.scriptTimeout` (60 s; tests override via
`Request.timeout`). Running async tasks can also be cancelled immediately by clicking the loading toast, which cancels in-flight fetch requests.

**Synchronous evaluations are capped.** A CPU-bound synchronous script cannot be interrupted
(`JSVirtualMachine.invalidate` no longer exists), so a stuck sync script would permanently park a
cooperative-pool thread. `OpenClipJSHost` refuses new synchronous evaluations (including the top-level
synchronous evaluation phase of async scripts) once `Constants.maxConcurrentSyncScriptEvaluations` (4)
are in flight — logging at `.error` and throwing — so thread accumulation stays bounded. (Once an async
script enters its promise pump loop, the sync gate is released while the watchdog + pump loop bounds the async phase.)

> **Compiler landmine:** inside the `Task.detached` closure, static members must be referenced by
> the explicit type name (`OpenClipJSHost.execute(...)`), never `Self.execute(...)`. `Self.x` in a
> detached-task closure trips a Swift 6 region-based-isolation checker bug (`"pattern that the
> region-based isolation checker does not understand how to check"`).

## Result Resolution

`OpenClipJSHost.run` resolves the outcome in a deterministic order:

1. A JavaScript exception → `.toast(.error, message)` (never thrown as a Swift error).
2. `requireConfiguration(...)` → `.openConfiguration`.
3. `toast(...)` — alone → `.toast`, or coexisting with effects → `.sequence([.toast, …effects])`.
4. Effects (paste/copy/pasteContent/copyContent/cut/openURL/keyPress/runShortcut/notify) → single
   `.paste`/`.copy`/etc, or `.sequence` of them when multiple were called. `pasteContent`/
   `copyContent` payloads are read via either key style (`public.utf8-plain-text`/`public.html`/
   `public.rtf` or `text`/`html`/`rtf`); a payload with none of the three is ignored (no effect).
5. String return value → `.text(string)` — implicitly returned text, delivered per the user's
   per-click preference (preview/paste/copy).
6. Otherwise → `.success`.

A JavaScript exception produces `.toast(.error, message)` instead of throwing; the toast dismisses
the popup by default (`keepVisible: true` keeps it open).

## Practical Examples

### Prettify JSON (returns a string → pasted)

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
