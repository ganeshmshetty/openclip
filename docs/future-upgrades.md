# OpenClip v2 Vision: Unified JavaScript Runtime

> **Status:** Future vision — not a current spec. Captured so the v1 design doesn't close this door.

---

## The Core Idea

Merge the JS-action host (`OpenClipJSHost`) and the canvas engine (`JavaScriptCanvasEngine`) into **one** `OpenClipJSEngine` — a bounded-session engine that powers *both* action kinds with a single, complete async runtime.

The difference between `type: "js"` and `type: "canvas"` becomes a **session contract** (run-once vs persistent), not a different engine.

---

## 1. One Engine, Two Contracts

| | `type: "js"` (Action Session) | `type: "canvas"` (Canvas Session) |
| :--- | :--- | :--- |
| **Lifecycle** | Mount → `action(selection, options)` → return result → session ends | `beforeMount` (async) → `ui(state)` → events → `onClose` |
| **Async surface** | Full — `await fetch` anywhere, even top-level | Full — `await fetch` in `beforeMount`, handlers, **and `ui()`** |
| **State** | Stateless | JSON `state` + private JS closure state |
| **Timers** | Available (auto-cancel on finish) | Available (auto-cancel on close) |
| **Push updates** | N/A | Engine can call `render()` mid-flight |

Both contracts share the *exact same* `CanvasScripting` protocol — `OpenClipJSEngine` is just a new conformer.

---

## 2. The Web/Async Shim Layer (The Real Unlock)

Installed in **every** context, this is what makes "any good library" actually run.

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

## 3. Unified Fetch (Single Source of Truth)

One `JSNativeFetch` helper (extracted from v1) used by both contracts:

- `installNativeFetch(in context:, session:, fetchTasks:)` — installs `openclip.__nativeFetch` + polyfills both global `fetch` and `openclip.fetch`
- Response: `{ status, ok, text(): Promise<string>, json(): Promise<any> }`
- Identical error rejection, headers, body, timeout (30 s watchdog)
- One test harness (`MockURLProtocol`) covers both

---

## 4. Optional Bundler Pipeline (esbuild at Install Time)

- Detects: `tsconfig.json` / `package.json` / `.ts`/`.tsx`/`.jsx` / multiple entry files
- Runs **esbuild** at install → emits single cached `.js` + source map
- Engine *only ever sees* the bundled plain JS
- Completely optional; single-file `.js` remains the default, zero-config path
- No module loader, no runtime TS, no `require()` — all compiled away

---

## 5. The Bridge Surface (Stable, Shared)

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
  showContent(tree: object, options?: { size?: { width: number; height: number } }): void;
  keepVisible(): void;
  requireConfiguration(payload: object): void;
}
```

---

## 6. Migration Path (No Big Bang)

| Step | What Happens | Risk |
| :--- | :--- | :--- |
| **v1 (now)** | Handlers-only `fetch` in canvas (as designed). Ship it. | Zero — additive, API-stable |
| **+Shim** | Add `setTimeout`/`URL`/`crypto`/etc. shim behind flag. Validate with real libs (`zod`, `marked`, `nanoid`). | Low — isolated, testable |
| **Engine swap** | `OpenClipJSEngine` conforms to `CanvasScripting`. Canvas sessions migrate; JS actions stay on `OpenClipJSHost`. | Medium — new engine, same protocol |
| **JS action migration** | Move `type: "js"` to the engine (run-once session contract). Delete `OpenClipJSHost`. | Medium — one codebase, one test suite |
| **Bundler** | Add esbuild-at-install (opt-in). Purely additive. | Low — separate pipeline |

---

## 7. Why This Is the Right End State

- **No duplicate engines** — current split (~800 lines × 2) is an artifact of "canvas added later." Unifying makes "async works" a property of the *runtime*, not the action kind.
- **The shim is the real unlock** — most think "modules = libs"; actually `setTimeout` + `crypto` + `URL` is what makes libs run. Bundling is just plumbing.
- **Protocol seam already exists** — `CanvasScripting` was built for exactly this swap. UI/session layer never changes.
- **Cost is honest but bounded** — the hard parts (execution bounding, teardown, error isolation) are a *single* effort on one engine.

---

## 8. What We Explicitly *Don't* Do

- **No `require()` / Node built-ins** — the shell runtime is the correct escape hatch for `fs`/`process`/subprocess. The JS runtime's job is "browser-grade logic in a popup."
- **No DOM / WebView** — typed `CanvasComponent` tree → SwiftUI renderer is a core product differentiator (privacy, validation, lightweight).
- **No out-of-process** — in-process JSC is the deliberate cost/benefit call for a floating popup. Raycast's Node is a different product class.

---

## 9. Appendix: v1 → v2 Compatibility

| v1 Feature | v2 Status |
| :--- | :--- |
| Canvas handlers-only `fetch` | Works identically (same `openclip.fetch`) |
| `isAsync: true` manifest flag | Becomes the gate for the full shim + timers |
| `ui()` synchronous | Becomes async-capable (but can stay sync) |
| `initialState` | Works; `beforeMount` adds async init |
| `handlers` returning promises | Works identically (same pump) |
| `showContent` at mount | Works identically; size declaration same |
| Test suite | Extended, not rewritten — same `CanvasScripting` contract |

---

*This vision exists so today's `JSNativeFetch` extraction, the `CanvasScripting` protocol, and the handlers-only scope all point at the same door. v1 ships value; v2 opens the door.*