# Extension Architecture: Trust Model & Runtime Privilege Tiers

This page documents **what an extension is allowed to do**, how OpenClip decides that, and where
the line is between malformed and untrusted. The authoritative manifest schema lives in
[`Extensions/AGENTS.md`](../../Extensions/AGENTS.md); this page is about the security
and trust posture.

Source of truth: `Sources/Core/Extensions/` (`ExtensionManager.swift`,
`Manifest/ManifestValidation.swift`, `Manifest/ExtensionManifestStore.swift`) and
`Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift`.

---

## 1. What an extension is

An extension is a **directory** (conventionally `<name>.openclipext`) containing an `openclip.json`
manifest plus optional script files and local assets, copied into `~/.openclip/extensions`. On
startup the app scans that directory, decodes each manifest, **validates** it, and registers one
action per manifest entry (or a group row + its sub-actions for `type: "group"`). There is no
compilation, sandbox, or approval step — a manifest plus an optional script is a complete
extension.

---

## 2. Trust model

> **Current reality (2026-08):** OpenClip treats an installed extension as **trusted code running
> with the user's privileges**. Installing an extension is an act of trust; OpenClip does not
> sandbox extension execution, prompt per-action, or quarantine packages.

Consequences of this model:

- **Installing = trusting.** `installExtension` copies a folder/archive/script into
  `~/.openclip/extensions` with no integrity or origin checks. Only the user decides what to
  install.
- **No sandbox.** Every runtime executes with the app's user context:
  - `shell`/`scriptfile` actions spawn real subprocesses (`/bin/zsh`).
  - `applescript` runs `NSAppleScript` with the user's Apple Events automation rights.
  - `keypress` posts synthetic keyboard events to the frontmost app.
  - `js` async mode can reach the network via a `fetch` polyfill, and the `openclip.*` bridge can
    paste/copy to the pasteboard, post notifications, run Shortcuts, and synthesize keys.
- **Validation is a correctness gate, not a security boundary.** The manifest validation pass
  (below) rejects *malformed* manifests (unknown action kinds, missing required fields, unknown
  capabilities). It does not — and cannot — make a malicious manifest benign. A "bad" extension is
  one that doesn't load, not one that is disarmed.

---

## 3. Manifest validation pass

Every manifest package is validated by `ManifestValidator`
(`Sources/Core/Extensions/Manifest/ManifestValidation.swift`) before any action is created. A
manifest that fails validation is **rejected as a whole** and the rejection is surfaced through
`Log.extensions` (category `extensions`) instead of being silently skipped.

Validation rules:

1. **Action kinds.** Each action's `type` (and each group sub-action's) must be a recognized kind
   (`ExtensionActionKind.recognizedTypeStrings`). Unknown kinds — previously silently mis-routed as
   `url` — now reject the package. Absent `type` still defaults to `url` (legacy manifests).
2. **Required fields per kind.** `keypress` requires `keyPress`; `shortcut` requires
   `shortcutName`; `group` requires non-empty `subActions`; every other runnable kind requires at
   least one of `url` / `script` / `scriptCode`. `service` requires nothing today.
3. **Capabilities.** Any declared `capabilities` entry outside the host's known set rejects the
   manifest (see §4).
4. **Bookkeeping.** Each validated manifest produces a `ManifestValidationRecord` carrying the
   host's supported **schema version** (`"1"`), the manifest's declared `version` when present, and
   a **SHA-256 content fingerprint** of the raw manifest bytes — logged on every successful load for
   observability (`Loaded extension manifest <id> (v<version>, schema 1, <n> action(s), sha256 …)`).

A manifest that fails to **decode** at all (malformed JSON, missing required `identifier`/`name`) is
also rejected and logged, via `ExtensionManifestStore.decodeManifest` (throwing), which replaced the
previous silent `nil`.

---

## 4. Capability gating (mechanism)

`ManifestCapabilityGate` is a generic mechanism: a manifest may declare `capabilities: [...]` and
the host validates them against a **known set**. The known set is intentionally **empty** on day
one, so:

- any non-empty `capabilities` list currently **rejects** the manifest (everything is unknown), and
- no capability slot is reserved or invented ahead of its runtime existing.

The mechanism stays generic so a future capability can be shipped by seeding
`ManifestCapabilityGate(knownCapabilities:)` (and therefore `ManifestValidator`) without reshaping
the loader. The empty-set state is exercised in tests: declare an unknown capability → load fails,
surfaced via the logging layer.

---

## 5. Runtime privilege tiers

Kinds are grouped by what they can reach on the system. Lower tiers are a subset of the ones above
for risk reasoning, but every kind executes without a sandbox — tiers describe *typical reach*, not
a containment boundary.

| Tier | Kinds | Reaches | Examples |
| :--- | :--- | :--- | :--- |
| L1 — text effects | `textsnippet`, `group` | pasteboard (paste replaced selection), structural rows only | wrap selection in markup; sub-menu container |
| L2 — network & pasteboard | `url`, `websearch`, `js` (sync) | open arbitrary URLs via LaunchServices, copy/paste clipboard | open a search page; prettify JSON into clipboard |
| L2+ — network + effects | `js` (`"async": true`) | L2 plus network `fetch`, notifications, `openclip.*` effects (keyPress, runShortcut, openURL, toast) | call an API and paste the result |
| L3 — subprocess / automation | `shell`, `scriptfile`, `applescript` | arbitrary command execution (`/bin/zsh`), Apple Events automation with the user's rights | run a formatter binary; drive Notes.app |
| L3+ — input injection & system | `keypress`, `shortcut`, `service` | synthetic key events to the frontmost app; run Shortcuts.app with the selection as input; macOS share picker | bold in the frontmost editor; run a "Trim" shortcut |

Notes:

- **`js` is the interesting one.** Synchronous JS runs in a `JSContext` with a read-only input and
  a fixed `openclip.*` effect bridge; async mode additionally reaches the network. Through the
  bridge it can already trigger L3-style effects (synthetic keys, Shortcuts, notifications) — the
  *intent* of the manifest author is the real capability boundary, which is why §2 says installing
  is trusting.
- **JS module containment is not a sandbox.** JS file scripts (`"script"`) resolve `require()` only
  inside their package directory — `../` and symlink escapes, absolute paths, and bare/Node-builtin
  specifiers are rejected (`OpenClipModuleLoader` + `Constants.isPathSafe`). This bounds a script's
  *file reads* to the package; it is not a privilege boundary (see §2 — JS still reaches the network,
  pasteboard, and `openclip.*` effects).
- **Subprocess watchdog.** Every subprocess-spawning runtime (`shell`, `scriptfile`, `shortcut`)
  is terminated past `Constants.scriptTimeout` (60 s) — a liveness guard, not a privilege guard. Users can also abort running loading tasks anytime by clicking the loading toast.
- **Secrets.** Option values of `type: "secret"` live in `SecretStore` (`~/.openclip/secrets.json` with POSIX 0600 permissions) and never reach UserDefaults or the manifest itself.

---

## 6. Failure surfacing

- Decode failure, validation rejection, and (via `DefaultActionFactory`) "no runnable content" all
  emit `Log.extensions`/`Log.factory` messages with the manifest path and, for validation, the
  full issue list. Filter in Console.app with `category == "extensions"` (or `"factory"`).
- Per-action drops that used to be silent (e.g. a script file that is missing or a directory) are
  now logged, so "my extension isn't showing up" is diagnosable.
- There is deliberately **no user-facing error UI** for a rejected manifest today; the package is
  simply not loaded and the reason is in the log. A future iteration may surface load failures in
  the Preferences → Extensions list.

---

## 7. Hot reload

Extensions are **re-scanned at launch and on every change** without relaunching.

`ExtensionsDirectoryWatcher` (`Sources/OpenClip/Platform/Extensions/ExtensionsDirectoryWatcher.swift`)
polls `~/.openclip/extensions` on a background queue and reloads via the same
`ExtensionManager.loadExtensions()` seam that startup uses. It is started by `AppDelegate` **after**
`ActionCoordinator.loadInitialState()` returns, so the `onRegister`/`onUnregister` registry wiring is
already in place before any watcher-triggered reload.

Mechanism (poll-snapshot diff, not FSEvents — pure Foundation):

- Each tick builds an `ExtensionsSnapshot`: a recursive fingerprint of the tree
  (relative path → content modification date), skipping hidden files (`.install_staging_*`,
  `.DS_Store`).
- A reload fires only when **two consecutive ticks agree** that the tree changed. The settle window
  keeps a reload from firing mid-copy while `cp -R`/download staging is still writing.
- On fire it hops to the MainActor and calls `loadExtensions()`; failures surface exactly as they do
  at startup (§6). Silent by design — a hot-reloaded rejection shows up in the log, not the UI.

Latency: one tick per second, so a settled change appears within ~2 seconds. `stop()` cancels the
timer (also used by tests; tests drive the settle logic synchronously via `pollOnce()`).
