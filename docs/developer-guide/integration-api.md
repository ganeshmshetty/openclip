# Integration & Automation API

OpenClip exposes an inbound `openclip://` URL scheme so other apps and scripts can trigger a small,
curated set of actions. This document is the **current-state contract**: what exists today, exactly
as implemented.

> **Status:** first iteration. The surface is deliberately small and **fire-and-forget**: a URL
> asks OpenClip to do one thing and nothing is returned. There is no settings read/write route, no
> x-callback-url reply, and no CLI yet; see [Not available yet](#not-available-yet).

---

## Availability

The command route is always available.

The `install` route is the existing extension-store flow and keeps its own source allow-list and
confirmation dialog.

---

## Routes

| URL | Purpose |
|-----|---------|
| `openclip://install?id=<id>&url=<https-url>[&name=<name>]` | Install a store extension (allow-listed + dialog) |
| `openclip://command/<name>` | Run an app-level command |

The scheme is `openclip` (registered in `Info.plist`). The host selects the route; matching is
case-insensitive. Routing and parsing live in `Sources/Core/Integration/OpenClipDeepLink.swift`;
the app performs the effects in `Sources/OpenClip/Platform/DeepLinkRouter.swift`.

### `openclip://install`

```
openclip://install?id=com.example.myext&name=My%20Extension&url=https%3A%2F%2Fopenclip.app%2Fmyext.zip
```

Downloads and installs a signed extension package. The download host must be on the allow-list:

```
github.com, release-assets.githubusercontent.com, objects.githubusercontent.com,
raw.githubusercontent.com, getopenclip.vercel.app, getopenclip.app,
www.getopenclip.app, openclip.app
```

A confirmation dialog is shown before installation. Malformed URLs (missing `id`/`url`) are ignored.

### `openclip://command/<name>` (commands)

App-level verbs.

```
openclip://command/open-settings
openclip://command/pause
openclip://command/resume
```

| Command | Effect |
|---------|--------|
| `open-settings` | Bring OpenClip's Settings window to the front |
| `pause` | Pause the popup for one hour (same as the menu bar's Pause) |
| `resume` | Clear a temporary pause |

---

## Why there is no settings route

Earlier iterations exposed `openclip://settings` (read), `openclip://set` (write), and an
x-callback-url reply. They were removed:

- **A URL scheme is unauthenticated.** Any local process can open `openclip://`, so a read/write
  settings route is an untrusted configuration API for every app on the machine.
- **A reply needs the wrong transport.** Returning a value required the caller to register a
  callback scheme and OpenClip to switch apps (`NSWorkspace.open`). Anything that needs a return
  value belongs in a CLI (stdout) or App Intents (return value).

The `openclip://` surface is therefore limited to side effects that neither read nor mutate
configuration.

---

## Not available yet

Candidates for a later iteration:

- **Running actions** (`openclip run <action-id>`) — headless invocation with the result on stdout.
  A CLI is the right transport for this, not a URL callback.
- **Capability discovery** (`openclip list --json`) — the runnable actions and their ids.
- **App Intents / Shortcuts integration** — `Run OpenClip Action`, `Capture Text`, and
  `Toggle OpenClip`, which return values natively.
- **macOS Services** — expose actions into the Services menu / context menu.

---

## Implementation map

| Concern | Location |
|---------|----------|
| URL grammar | `Sources/Core/Integration/OpenClipDeepLink.swift` |
| Dispatch + install | `Sources/OpenClip/Platform/DeepLinkRouter.swift` |
| Command side effects | `Sources/OpenClip/Settings/IntegrationSettings.swift` |
| Entry point | `AppDelegate.application(_:open:)` → `DeepLinkRouter.shared.handle(_:)` |
| Tests | `Tests/OpenClipTests/DeepLinkTests.swift` |
