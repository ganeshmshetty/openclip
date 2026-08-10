# Logging

OpenClip logs through a single surface — `Log` (`Sources/Core/Log.swift`) — so every message
belongs to a stable, greppable subsystem category and is filterable from the command line or
Console.app. There is no ad-hoc `print()` anywhere in `Sources/`.

## The `Log` enum

Each subsystem owns a fixed `os.Logger` on `com.openclip`:

| Category         | Owns                                                        |
| :--------------- | :---------------------------------------------------------- |
| `settings`       | `SettingsStore` paths, rule load/save, launch-at-login, AI config persistence (Keychain), installed-app scanning |
| `presentation`   | popup/panel UI, hover, action-run error surfacing, status bubbles |
| `chrome`         | popup window chrome & sizing (currently unused — reserved)  |
| `factory`        | action factory, extension manifest authoring (Add/Edit sheets) |
| `result-handler` | post-action effect handling (paste, calendar write, etc.)   |
| `coordinator`    | action coordination / enablement evaluation                 |
| `shell`          | `ShellProcessRunner` (subprocess watchdog, timeout)         |
| `js`             | `OpenClipJSHost` runtime                                    |
| `selection`      | `MacTextRetriever` / `MacSelectionMonitor` (AX + pasteboard + keyboard retrieval) |
| `extensions`     | `ExtensionManager`, remote installer, extension store/onboarding install & uninstall, **manifest decode/validation rejections** |
| `ai`             | AI providers and preset persistence                         |
| `permissions`    | TCC / accessibility permission management                   |
| `icons`          | icon fetching/caching (`UnifiedIconProvider`, icon picker)  |

**Add a new category when a new subsystem starts logging.** Never create a raw
`Logger(subsystem:category:)` at the call site — extend `Log` and keep this table in step.

## Conventions

- **Levels:**
  - `.notice` — lifecycle transitions (install/uninstall, download start/success, permission fallbacks).
  - `.info` — durable, useful state (rules loaded/saved counts).
  - `.error` — recoverable failures that still surface to the user (manifest write failure, action throw).
  - `.fault` — reserved for multi-process crashes / invariant violations (currently none).
  - `.debug`/`.warning` — diagnostic detail and soft failures (defensive parses, transient network).
- **Structured & greppable:** include the action id, extension id, and/or error domain. e.g.
  `Log.extensions.error("Failed to load extension from <path>: <error>")`.
- **Privacy:** anything touching selected text, clipboard content, or extension-authored data stays
  default-private. Only ids and URLs are marked `privacy: .public` (e.g.
  `\(action.id, privacy: .public)`). Do not mark user text `.public`. JS script `console.log` arguments
  are redacted into structural metadata (`<string len=N>`, `<Object keys=[...]>`) before logging.
- **No hot-path logging:** never log in per-mouse-move hover updates or high-frequency view bodies.

## Filtering workflow

All categories share subsystem `com.openclip`, so filter by category:

```sh
# Live tail for a subsystem (e.g. extensions)
log stream --predicate 'subsystem == "com.openclip" && category == "extensions"'

# Debug builds only (release strips info-level spam); include level
log stream --predicate 'subsystem == "com.openclip" AND category == "selection" AND messageType >= 1'

# Last N messages from disk
log show --predicate 'subsystem == "com.openclip"' --last 1h
```

In Console.app: filter `subsystem == "com.openclip"`, then narrow by category.

## In-process debug log (experimental)

OpenClip keeps a small in-memory ring buffer of recent `com.openclip` entries in the App
target (`DebugLogStore`, `Sources/OpenClip/Platform/DebugLogging/`) so agents and developers
can read recent logs without Console.app. It is fed by reading the current process's own
unified-log stream via `OSLogStore(scope: .currentProcessIdentifier)` — `Log` itself is
untouched. Noteworthy behaviours:

- **Readback requires a live process.** Entries are only readable while the owning process is
  running; after it exits the unified log may not persist them (this is why `log show` after
  process termination can print nothing). The CLI dump therefore captures the *current* process.
- **Privacy is preserved.** `privacy: .public`/`.auto` values show in full; `.private` shows as
  `<private>` — same as external tooling.
- **The store runs only during `--dump-logs`.** Normal app launches never start it: each poll is
  an `OSLogStore` scan that keeps `OSLogService.xpc` burning double-digit CPU for the process's
  whole lifetime. The `--dump-logs` path starts it, dumps, and exits.

### `--dump-logs` CLI

Run the app binary directly (not via `dev_run.sh`):

```sh
"/path/to/OpenClip.app/Contents/MacOS/OpenClip" --dump-logs --category=extensions --level=error
```

Flags: `--category=`, `--level=`, `--count=`, `--collect=` (seconds, default 4), `--help`.
It cold-launches the app, runs extension loading (so load/reject lines are produced), waits,
then prints the last N lines to stdout and exits 0 (`2` on usage errors). This is the quickest
agent check for "did my extension load or reject?".
