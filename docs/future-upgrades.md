# OpenClip v2 Vision: One JavaScript Action Runtime

> **Status:** Future vision — not a current spec. Captured so the v1 design doesn't close this door.

---

## The Core Idea

Today `OpenClipJSHost` powers `type: "js"` actions with a bounded session runtime (run-once:
mount → `action(selection, options)` → return result → session ends), and async-mode JS reaches
the network through the shared `JSNativeFetch` bridge. (An interactive canvas runtime once sat
alongside it; that surface has been removed — the JS **action** runtime is the only remaining
JavaScript surface.)

The v2 vision is to keep hardening that one runtime into a complete async engine: first-class
web shims, unified fetch, and optional bundling — so "any good library" runs in a popup.

---

## 1. The Web/Async Shim Layer (The Real Unlock)

Installed in the JS context, this is what makes "any good library" actually run.

| Shim | Bridged To | Why It Matters |
| :--- | :--- | :--- |
| `setTimeout` / `setInterval` / `clearTimeout` | `DispatchSourceTimer` | Enables timers, polling, debounce, all scheduling patterns |
| `queueMicrotask` | Native JSC promise queue | Library expectations |
| `URL` / `URLSearchParams` | Pure JS polyfill | Browser-standard URL handling |
| `TextEncoder` / `TextDecoder` | Pure JS polyfill | Unicode/encoding (zod, etc.) |
| `crypto.getRandomValues` | `SecRandomCopyBytes` | UUIDs, `nanoid`, any crypto needs |
| `AbortController` / `AbortSignal` | Pure JS | Fetch cancellation |
| `performance.now` | `CACurrentMediaTime()` | Timing, animations |
| `fetch` (global + `openclip.fetch`) | Existing URLSession bridge | Network I/O — unified impl |

**With this shim:** `lodash`, `date-fns`, `dayjs`, `zod`, `marked`, `papaparse`, `nanoid`, `uuid`, `axios` (with adapter), `slugify`, `gray-matter`, `he`, `snake-case` — all just work.

**Still won't work (by design):** Node built-ins (`fs`, `process`, `stream`, `os`, `path`, `child_process`), native addons (`sharp`, `better-sqlite3`), DOM libraries (React-DOM, jQuery). The shell/AppleScript runtime already covers system access.

---

## 2. Unified Fetch (Single Source of Truth)

The `JSNativeFetch` helper (already extracted in v1) is the one network path:

- `installNativeFetch(in context:, session:, fetchTasks:)` — installs `openclip.__nativeFetch` + polyfills both global `fetch` and `openclip.fetch`
- Response: `{ status, ok, text(): Promise<string>, json(): Promise<any> }`
- Identical error rejection, headers, body, timeout (30 s watchdog)
- One test harness (`MockURLProtocol`) covers the JS runtime

---

## 3. Optional Bundler Pipeline (esbuild at Install Time)

- Detects: `tsconfig.json` / `package.json` / `.ts`/`.tsx`/`.jsx` / multiple entry files
- Runs **esbuild** at install → emits single cached `.js` + source map
- Engine *only ever sees* the bundled plain JS
- Completely optional; single-file `.js` remains the default, zero-config path
- No module loader, no runtime TS, no `require()` — all compiled away

---

## 4. The Bridge Surface (Stable, Shared)

```typescript
interface OpenClipBridge {
  // Read-only context
  input: { text: string; matchedText: string; captures: string[]; app: { bundleID: string; name: string } };
  options: Record<string, string>;
  option(id: string): string | undefined;

  // Effects (all async-safe, collected in call order)
  paste(value: string): void;
  copy(value: string): void;
  cut(value: string): void;
  openURL(urlString: string): void;
  keyPress(key: string, modifiers: string[]): void;
  runShortcut(name: string): void;
  notify(title: string, body: string): void;
  showStatus(message: string, style?: "success" | "error" | "info"): void;
  keepVisible(): void;
  requireConfiguration(payload: object): void;
}
```

---

## 5. Migration Path (No Big Bang)

| Step | What Happens | Risk |
| :--- | :--- | :--- |
| **v1 (now)** | `OpenClipJSHost` with async-mode `fetch` + the `openclip.*` bridge. Ship it. | Zero — additive, API-stable |
| **+Shim** | Add `setTimeout`/`URL`/`crypto`/etc. shim behind flag. Validate with real libs (`zod`, `marked`, `nanoid`). | Low — isolated, testable |
| **Bundler** | Add esbuild-at-install (opt-in). Purely additive. | Low — separate pipeline |

---

## 6. Why This Is the Right End State

- **One runtime, one async story.** Making "async works" a property of the *runtime* means every
  JS action gets the same execution bounding, teardown, and error isolation.
- **The shim is the real unlock** — most think "modules = libs"; actually `setTimeout` + `crypto` + `URL` is what makes libs run. Bundling is just plumbing.
- **Cost is honest but bounded** — the hard parts (execution bounding, teardown, error isolation) are a *single* effort on one engine.

---

## 7. What We Explicitly *Don't* Do

- **No `require()` / Node built-ins** — the shell runtime is the correct escape hatch for `fs`/`process`/subprocess. The JS runtime's job is "browser-grade logic in a popup."
- **No WebView** — JS runs in-process in a `JSContext`; that is the deliberate cost/benefit call for a floating popup. Raycast's Node is a different product class.
- **No out-of-process** — in-process JSC keeps the popup lightweight and private.

---

## 8. Appendix: v1 → v2 Compatibility

| v1 Feature | v2 Status |
| :--- | :--- |
| `openclip.fetch` / global `fetch` (async mode) | Works identically (same `JSNativeFetch`) |
| `isAsync: true` manifest flag | Becomes the gate for the full shim + timers |
| `openclip.*` effects | Works identically (same bridge surface) |
| Test suite | Extended, not rewritten — same `JSNativeFetch` seam |

---

*This vision exists so today's `JSNativeFetch` extraction and the async-mode scope all point at the same door. v1 ships value; v2 opens the door.*
