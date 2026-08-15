# PopClip Extension System — Reference & Design Notes for OpenClip

> **Research target:** How PopClip (macOS, Nick Moore / Pilotmoon) implements and distributes its
> extensions, mapped to OpenClip's design questions. Compiled from **primary sources only** — the
> official developer docs, the official user guide, the developer's own release announcements, and
> real extension packages in the first-party GitHub repo. Source URLs are cited per claim; facts and
> inference are labelled. Current app version referenced: **PopClip 2026.7.1 (5997)**, docs current
> as of Aug 2026.

---

## TL;DR for OpenClip designers

**What PopClip is:** a single-extension-per-decision, **declarative manifest that doubles as the
`Config` file**, optionally backed by code. An extension is a `.popclipext` folder (or a plain-text
`#popclip` snippet). It can bundle arbitrary files (icons, scripts, readmes). The manifest sets
metadata, `actions` (one of 7 declarative types), filter `requirements`, `options`, and an
`app`/dependency gate. When a script action is present, the script itself is the manifest.

**Model parity with OpenClip's `.openclipext`:** OpenClip's package format (directory +
`openclip.json` manifest + scripts + local icons, action kinds url/javascript/applescript/shell/
shortcut/service/group, options incl. Keychain `secret`, `requirements` regex/apps/requiredOptions,
primary/secondary result delivery via `secondary`/`toast`/`secondaryToast`) is clearly modelled on
the same lineage. The two are close cousins.

**Meaningful capabilities PopClip has that OpenClip currently lacks** (from OpenClip's developer-guide):

| Capability (PopClip) | OpenClip today | Source |
| :--- | :--- | :--- |
| **Curated, hosted marketplace** serving `.popclipextz`, discovery RSS, per-extension version + install-dependency metadata. | Manual `cp -R` into `~/.openclip/extensions`; no hosted store. App scans the folder at startup. | [dir], [rss], OpenClip `package-format` §1. |
| **Signed packages + validation status + unsigned code gates.** `_Signature.plist`; installs signed without warning; unsigned with Shell/AppleScript/entitlements → warning dialog. `defaults` flags to toggle. | No signature, no trust/prompt model. | [dev], [extensions-guide] |
| **Auto-update of installed extensions** (new in 2026.7) + "Manage Extensions" sheet. | No update mechanism. | [rel2026.7], [extensions-guide] |
| **iCloud sync of extensions + action layout + settings + secrets**, optional. | No sync. | [rel2026.7] |
| **Rich JS/TS runtime**: CommonJS `require()` of files *and ~20 bundled npm libs* (axios, linkedom, turndown…), XHR/network via `network` entitlement, async/await + settle-flag spinner, dynamic action population function, submenus, JSON<->plist, TypeScript transpile, `auth`/OAuth sign-in flow with keychain `authSecret` + `expiresIn`. | JS host is inline JS (JavaScriptCore) bridge with `openclip.*` effects + optional async+`fetch` polyfill; no module/`require`, no TS, no xhr entitlement, no sign-in flow. | [js-env], [js-actions], [js-modules], [changelog] |
| **Contextual requirement vocabulary**: `url`, `isurl`, `urls`, `email`/`emails`, `path`, `paste`, `cut`, `formatting`, `option-foo=bar`, and **text narrowing** (a `url` req narrows the working text to the detected URL; `popclip.input.regexResult`, `fullText`). | `requirements` are regex + apps allow/deny + requiredOptions; no URL/email/path/paste/format detectors or text narrowing. | [actions] |
| **`before`/`after` orchestration steps** (`copy/cut/paste`, `paste-plain`, `copy-selection`, `popclip-appear`; then `copy-result`/`paste-result`/`preview-result`/`show-result`/`show-status`) | No `before` step; **delivery replaces `after`** — a declared `secondary` result per click (non-JS kinds; JS branches on `openclip.input.isSecondaryClick`) plus per-click `toast`/`secondaryToast`, with a derived paste→copy default and a probe that downgrades paste to copy when the target can't paste. No `show-status`/`preview-result`. | [actions] |
| **`app` dependency gate**: `checkInstalled` + `bundle identifiers` + install link | Only bundle-id filter for reveal, no "install me if missing" | [actions] |
| **Options UI & option types**: `string`/`boolean`/`multiple`/`secret`(Keychain)/`heading`; `multiline`, `allow other`, `allow none`, `value labels`, `inset`, icon-on-boolean, clickable links in description; sign-in "auth service label" | `string`/`boolean`/`multiple`/`secret`(Keychain) in Preferences; no multiline/allow-other/heading/links or sign-in UI | [config], [changelog] 2026.7 |
| **Icon spec system** — text ("ABC"), SF Symbol, Iconify (200k), inline SVG/data URI, PNG/SVG file, and modifiers (`square filled circle search strike`, `flip-x`, `scale=…`, `rotate=…`, `preserve-color`, `monospaced`) | icon is `symbol(...)` SF Symbol / local file / bare name | [icons] |
| **Folders→submenus, separators, page-break, per-action "show as" icon/text, multiple instances with custom name/icon, unlimited actions** | single action per entry; group rows with sub-menus exist; no folder tree/duplicates/separators | [rel2026.7], [extensions-guide] |

**What PopClip deliberately does NOT do** (evidence beneath the table, §"Not supported"):

- Grant extensions independent background execution or rich interactive content. JS runs in a sandbox that "cannot access the filesystem"; output is limited to inline result text / badges and the bar, not an embedded HUD. (Js-env.)
- Let an individual extension define a persistent, app-like chrome or long-running HUD/notification
  that survives beyond the popup action button; the interaction is a single trigger → single result
  in the bar.
- (Inference, low confidence) expose a global hotkey mechanism per-extension.

---

## 1. Package & file format

### Snippet vs Package — two install formats

PopClip docs define **two** flavors of an extension:

| | Snippet | Package |
| :-- | :-- | :-- |
| What it is | Plain text in YAML 1.2, first line `#popclip` (or `# popclip`), ≤ ~5000 chars | Folder containing a `Config.*` file plus optional icons/scripts/README |
| Install | Click "Install Extension …" in the popup bar for the selected text | Double-click the `.popclipext`/`.popclipextz` file |
| Distribution | Copy/paste as text (forums, pastebins) | Download as a file |
| Signing | Not signed | Can be signed |
| File extensions | None (selection) or `.popcliptxt` text file | `.popclipext` folder, `.popclipextz` zipped folder |

Source: [dev/](https://www.popclip.app/dev/), [snippets], [packages].

A snippet can do everything a package can except reference external files ([snippets]).
Snippets ≥5000 characters ("5000 char limit", raised from 1000, via [changelog]).

### The Config file

Every extension is a dictionary config ([config]). The `Config` file is resolved by case-sensitively
looking inside the package root for a file with base name `Config`:

| File | Format |
| :-- | :-- |
| `Config.plist` | Apple XML Property List (the original; author recommends avoiding — verbose) |
| `Config.json` | JSON (parsed with a JSON parser, not YAML) |
| `Config.yaml` | YAML 1.2 |
| `Config.js` / `Config.ts` | JavaScript or TypeScript **module** (see § "Module-based") |
| anything else / bare `Config` | Snippet content |

Source: [packages], [changelog] (JSON parsing change, 2024.3), [platform] note.

**Key names are flexed:** PopClip standardizes names to "lowercase with spaces" and accepts
`Key Name`, `keyName`, `KeyName`, `key_name`, `key-name`, `KEY_NAME` all as equivalents; a legacy
mapping table maps old names (e.g. `regular expression` → `regex`, `java script file` →
`javascript file`, `blocked apps` → `excluded apps`). Prefixes `extension`/`option` are stripped ([config]).

### Manifest schema

Top-level (all optional except `Name`): `name`, `icon`, `identifier`, `description`,
`macos version` (e.g. `11.0`), `popclip version` (integer build, e.g. `4151`), `options` (array),
`entitlements` (JS only: `network`, `dynamic`), `action`/`actions` (dict or array), `submenu`
(array), `show as` (`icon`/`text`), `auth service label`, `offers multiple instances`… ([config]).

`identifier` must be alphanumeric + `.` and `-` only, should be globally unique reverse-DNS;
`com.pilotmoon.` and `app.popclip.` prefixes are reserved for signed extensions ([config], [changelog]).

**Primary example** — the published **Yoink** extension config (real ground truth,
[config] reproduces it):

```json
{
  "identifier": "at.EternalStorms.Yoink.PopClipExtension",
  "popclipVersion": 3785,
  "name": "Yoink",
  "icon": "yoink.png",
  "app": {
    "name": "Yoink",
    "link": "https://eternalstorms.at/yoink/mac",
    "checkInstalled": true,
    "bundleIdentifiers": ["at.EternalStorms.Yoink", "at.EternalStorms.Yoink-setapp", "at.EternalStorms.Yoink-demo"]
  },
  "serviceName": "Add Selected Text to Yoink",
  "captureHtml": true,
  "description": "Add the selected text to Yoink."
}
```

### Icons — a whole mini-language

The icon value is a **text specifier string**: optional "modifiers" followed by a **base icon**.
([icons])

- **File icons**: path to `.png`/`.svg` in the package (package-only), ≥256px, monochrome shape on
  transparent ground. Prefix `file:`.
- **Text icons**: `T`, `ABC` (≤3 chars), `@`, `本`, `()`, even emoji (emoji render in color);
  prefix `text:` optional; `monospaced` uses monospace variant.
- **SF Symbols**: `symbol:<name>` (macOS ≥11), monochrome.
- **Iconify**: `iconify:<set>:<name>` → 200,000+ icons from open-source sets; colored ones
  auto-render in color.
- **SVG source**: `svg:<inline-svg-string>`.
- **Data URI**: `data:image/…` (SVG or PNG).

Modifiers: style `square`/`circle`/`search`/`strike`/`filled`/`monospaced`; transforms `flip-x`,
`flip-y`, `move-x=…`, `move-y=…`, `scale=…`, `rotate=…`; color/aspect `preserve-color`,
`preserve-aspect`. Example: `search filled T`, `square filled iconify:mdi:home`, `rotate symbol:signpost.right`.
([icons])

This is far richer than OpenClip's `symbol(Name)`-or-local-file icon string ([package-format §3]).

---

## 2. Action types / capabilities

An extension defines **one or more actions**, each one of **seven** types ([dev overview]):

| Type | What it does |
| :-- | :-- |
| **URL** | Open a URL with selected text inserted as query (placeholder `***` = `https://…`?q=…) |
| **Key Press** | Press a key combination (`key combo` / `key combo` string) |
| **Service** | Send text to a macOS **Services** menu service (`service name`) |
| **Shortcut** | Run a macOS **Shortcut** by name (macOS 12+) |
| **Shell Script** | Run a shell script (`shell script` / `shell script file`, e.g. `.zsh`) |
| **AppleScript** | Run an AppleScript (`applescript` / `applescript file`, incl. `.scpt`) |
| **JavaScript** | Run JS/TS in PopClip's sandboxed **JavaScript environment** |
Source: [dev/] table; each type has its own page: [url-actions], [key-press-actions], [service-actions], [shortcut-actions], [shell-script-actions], [applescript-actions], [js-actions].

### Common action properties (all optional)

`title`, `icon`, `identifier` (passed to scripts), `before`, `after`, `app` dict, `stay visible`,
`capture html`, `capture rtf`, `restore pasteboard`, `requirements` array, `regex`, `required apps`,
`excluded apps`. Properties can live at the extension top level, in an `action`, or in an `actions`
array; top-level set properties act as defaults for the array ([actions]).

### The `requirements` vocabulary (contextual gating — OpenClip maps to `requirements` + gating)

A `requirements` array filters whether an action appears; any requirement can be negated with `!` ([actions]):

- `text` (default when omitted), `copy` (synonym)
- `cut` — text selected **and the app's Cut is available**
- `paste` — app's **Paste available**
- `url` — text *contains* exactly one web URL (http/https)
- `isurl` — text *is* a single valid URL (added 2024.12)
- `urls` — one or more URLs
- `email` / `emails` — one / one-or-more email addresses
- `path` — text is a local file path that **exists on disk**
- `formatting` — the text field supports rich formatting
- `option-<foo>=<bar>` — enables/disables via option value (boolean → `1`/`0`)

### `regex` and text-narrowing "side effects"

`regex` (ICU) is applied after `requirements`; if it matches the *narrowed* text the action shows and
the matched substring is what's passed to the action. The `url`/`isurl`/`email`/`path` requirements
also *narrow and normalize* the working text (e.g. `url` prepends `https://` to scheme-less),
and scripts read narrowed text vs full via `POPCLIP_TEXT`/`POPCLIP_FULL_TEXT` (Shell/Apple) or
`popclip.input.matchedText` (full: `popclip.input.text`), plus `regexMatch`/`regexResult` capture
groups ([actions]). OpenClip's `{matched}`/`{captureN}` supports the regex narrowing; it has none of
the URL/Email/path detectors.

### The `before` and `after` orchestration

- `before`: `cut`, `copy`, `paste`, `paste-plain` (reduce clipboard to plain text then paste).
- `after`: `copy-result`, `paste-result` (paste+copy; else copy), `preview-result` (copy + show
  truncated 160‑char preview, clickable to paste), `show-result` (copy + show truncated),
  `show-status` (tick/cross), `cut`, `copy`, `paste`, `paste-plain`, `popclip-appear` (re-trigger
  popup, used by Select-All), `copy-selection` (put original selection on clipboard; used by Swap).
  ([actions])

### Script input/output

- Shell/AppleScript receive `POPCLIP_TEXT`, `POPCLIP_FULL_TEXT`, options as `POPCLIP_OPTION_*`
  (Shell) / `{popclip text}` + AppleScript vars; scripts printf stdout.
- JS actions are wrapped as `async function main()`; the return string feeds the `after` step; errors
  thrown → shaking-X; `throw "Settings error: …"` / `"not signed in"` pops the settings sheet.
  ([js-actions])

---

## 3. Marketplace / store / updates (primary)

- **Storefront:** https://www.popclip.app/extensions/ — a **curated** directory hosted on
  `www.popclip.app`; lists ~219+ extensions with categories (Text Editing, AI Tools, Markdown, …),
  A–Z / New / Updated. It is run by PopClip's author, Nick Moore ("The PopClip Extension Directory is
  curated by me, and I will not publish all submissions. I may also modify submissions before
  publishing them."). ([extensions-page], [extensions-repo-README])

- **Repository process:** The open-source repo is the *store's source*: extensions live in
  `source/` (maintained+supported) and new/contributed/niche ones go in `contrib/` (unpublished,
  not supported). Submissions must be **source-only, no compiled binaries**, no phone-home, and
  favour JS over Shell/AppleScript. ([extensions-repo README])

- **Download mechanism / file serving:** each extension's "Download" button hits
  `https://public.popclip.app/extensions/ext_<id>/file` returning the packaged file
  ([Yoink detail]). Extension icons render via
  `https://icons.popclip.app/icon?cache=<n>&specifier=<icon-spec>` — a remote rendering service that
  turns icon specifier strings into PNGs ([directory page HTML]).

- **Discovery: RSS** — `https://public.popclip.app/extensions/popclip.rss` publishes every directory
  publication with title, GUID (identifier), date, link. This feed is how the ecosystem (and the
  app) can learn new/updated extensions ([rss]).

- **Versioning:** extension `version` is surfaced (e.g. "Version 100" on the Yoink page) and
  `identifier` unifies an extension across updates. Every directory page shows "Created, Version,
  Identifier, PopClip Version (≥), macOS Version (≥), Action Type, License, Source". ([Yoink detail])

- **Updates & auto-update:** Introduced in **PopClip 2026.7**: "**Extensions auto-update:** Extensions
  from the PopClip Extensions Directory can now update to the latest version automatically." A new
  **Manage Extensions** sheet lets you turn "Update automatically" on/off and check for updates; a new
  **Extension Info** sheet shows origin, version, signature, installer info. ([relnotes-2026.7], [extensions-guide])

- **Sync:** the same 2026.7 release added **iCloud sync** of installed extensions, the action layout,
  and action settings (+ per-action secrets via iCloud Keychain). ([relnotes-2026.7], [kb-sync])

No public per-extension **download-count** or "recommended" surfaced numbers were visible on the pages
fetched (categories + recent-arrangement, not counts) — noted as an observation, not a claim.

---

## 4. Configuration UI

### Extension options → Preferences UI

Options are an array in the config; they appear to the user in **PopClip's own settings/preferences
UI** (the "Actions" pane), and are stored by PopClip:

| Option type | UI |
| :-- | :-- |
| `string` | text field (`multiline: true` for multi-line) |
| `boolean` | checkbox (optional `icon` next to it) |
| `multiple` | multiple-choice list (`values`; optional `value labels`, `allow other`, `allow none`) |
| `secret` | concealed; **saved in macOS Keychain** (never Prefs). Added 2024.3; 2026.7 adds a reveal "eye" |
| `heading` | text heading, no value |

Option dict fields: `{ identifier, type, label, description (with clickable links, Markdown or bare
URLs, since 2026.7), default value, values, value labels, inset, icon, multiline, allow other,
allow none }` ([config], [changelog]).

### Sign-in / authentication UI

Extensions that need a user account use a JS `auth()` function; PopClip shows "Sign in to your
\<label\> account". Result can be a `{ secret, label, expiresIn }` object (2026.7); the *signed-in
account name* can then be shown in settings. ([config], [changelog] 2026.7)

### How extensions surface in Preferences without scripting

The **Actions tab** lists every action; the **Extensions ** tab (or Actions → Tools → "Manage
Extensions…" `⌘E`) lists installed extension packages with origin, version, signature, source dir.
"View Source" opens a folder copy; "View Web Page" opens the directory page. ([extensions-guide])

---

## 5. Permissions / trust model

- **No sandbox for OS processes** — shell/AppleScript run outside the app (with scripting permission
  on macOS 10.15+ for AppleScript). Arbitrary executable code is the norm; the docs are explicit:
  "PopClip extensions can contain arbitrary executable code. Be careful…" ([dev overview])

- **Signing.** Published packages are **digitally signed** (`_Signature.plist` is a reserved filename
  in a package). Signed packaged install without warning. **Unsigned warning:** extensions containing
  Shell Script actions, AppleScript actions, or JS with entitlements show a warning dialog on install
  (snippet style, JS-without-entitlement, etc. don't). The unsigned warning only taps when the code
  "has the potential to access files … or access the internet" ([extensions-guide]). Dev overrides
  via `defaults write com.pilotmoon.popclip LoadUnsignedExtensions -bool YES` and
  `AllowUnsignedReservedPrefixes`. ([dev overview])

- **JS sandbox.** JS runs in **JavaScriptCore** in a sandbox that "cannot access the filesystem".
  Network only via a provided `XMLHttpRequest` (IF the extension declares the `network` entitlement),
  restricted to `https:` (ATS; localhost allowed since 2024.12). No direct FS, no arbitrary socket;
  `network` and `dynamic` entitlements are declared in config. ([js-environment], [config])

- **Secrets.** `secret` options and sign-in secrets live in the **Keychain**; since 2024.4, replacing
  a signed extension with an unsigned one purges its `secret` options ([changelog]). iCloud-sync'd
  secrets go through iCloud Keychain (2026.7, [relnotes]).

- **No user consent prompt per-run** for scripts — install-time is where gating happens (warning dialog
  for unsigned). Script execution itself doesn't prompt each occurrence.

---

## 6. UX integration (contextual bar)

- Actions appear in the popup **only when the selection satisfies their `requirements`, `regex`,
  `required apps` / `excluded apps`, and `app` dependencies** — so PopClip is effectively as
  contextual as OpenClip's.
- `app` dict can be set to a starter app-licensed ("Works With" app) and, when `checkInstalled:true`,
  PopClip shows a "install this app" message with a link if it's not present. This is **app‑gating +
  dependency** beyond OpenClip's app-allow/deny filter. ([actions])
- 2026.7 added **folders/submenus, separators, page‑breaks, per‑action "show as" icon/text**, and a
  "More" overflow with page position; the bar now expands to use more screen width and can hold
  "unlimited" actions ([relnotes-2026.7]).
- **Submenu** actions (new 2026.7): click main button, secondary‑click shows a submenu of
  supplementary actions; supports JS function‑generated submenus (`dynamic` entitlement). Maps to
  OpenClip's group/sub-action palette concept but natively rendered as menus/submenus. ([actions-submenu], [js-modules-submenu], [changelog-2026.7])
- **Filtering via modifiers**: holding ⌥ invokes "verbatim search" wrapping in quotes (since 2026.7)
  ([changelog-2026.7], [relnotes]).

---

## 7. What PopClip does NOT support (gaps OpenClip could differentiate on)

1. **Persistent, engine-heavy "rich interactive" extension UI.** The JS env is a **sandbox that
   cannot access the filesystem**; the only rich output surfaces are the popup bar icons/titles,
   `popclip.showText` (compact or large "type" display), badges/status, and `show-result` preview
   text. There is no embedded pane/webview/ext-enrichment that survives the clip pop — the extension
   runs when triggered and its "interface" is a button + optional script result. ([js-env], [js-actions])
2. **No always-on app-space background / widget.** Extensions have no independent UI surface or
   system‑wide events beyond what PopClip's popup host provides.
3. **Per-extension full keyboard-controllable hotkey** (a hand-wired "click this button" is the only
   Trigger). There is no documented `hotkey`/shortcut field in the action schema (the app-level ⌥⌘…
   popup toggle is global, and that's it). The *action* type "Key Press" is about emitting a keypress
   *to the front app*, not catching one. (Inference from absence across the full schema; label as such.)
4. **Arbitrary client-side app code.** Extensions are JS/Shell/AppleScript/Services/Shortcuts/URL/
   keycombo only — there is no way to execute compiled native code (repo explicitly rejects compiled
   binaries) ([config-repo]).

---

## Cited sources (primary)

PopClip official developer reference:
- https://www.popclip.app/dev/ (introduction: snippet/package table, 7 action types, signing, filter rules)
- https://www.popclip.app/dev/config (config dict, keys, options array, identifiers, key-name mapping)
- https://www.popclip.app/dev/packages (package folder, `Config.plist/.json/.yaml/.js/.ts`, reserved names)
- https://www.popclip.app/dev/snippets (`#popclip`, size limits, inverted syntax, `.popcliptxt`)
- https://www.popclip.app/dev/icons (icon specifier language, base formats, modifiers)
- https://www.popclip.app/dev/actions (common props, `requirements`, `regex`, `before`/`after`, `app` dict, submenus)
- https://www.popclip.app/dev/url-actions · key-press-actions · service-actions · shortcut-actions
- https://www.popclip.app/dev/shell-script-actions · applescript-actions
- https://www.popclip.app/dev/js-actions (JS actions, function wrapper, error signaling)
- https://www.popclip.app/dev/js-environment (JS sandbox "cannot access filesystem", globals `popclip`/`pasteboard`, bundled npm libs, `require()`, network+`network`, TypeScript, test harness `run`)
- https://www.popclip.app/dev/js-modules (Module-based, `Config.js/.ts`, static-only props, population fn, submenu functions, entitlements)
- https://www.popclip.app/dev/changelog (2026.7 submenus/show-as, 2024.x JSON/`secret`, historical key renames)

PopClip user guide & knowledge base:
- https://www.popclip.app/guide/extensions (extensions vs action, install `.popclipextz`, unsigned warning, Manage Extensions / auto-update / Extension Info / View Source)
- https://www.popclip.app/guide/ (What is PopClip)
- https://www.popclip.app/kb/sync (iCloud sync) · https://www.popclip.app/kb/paths (storage)

Directory & distribution:
- https://www.popclip.app/extensions/ (directory homepage, list)
- https://www.popclip.app/extensions/x/7qrrqm (Yoink detail: Download button, Version, Identifier, min popclip/macOS, Source link)
- https://public.popclip.app/extensions/popclip.rss (realtime RSS discovery feed)
- https://public.popclip.app/extensions/ext_…/file (extension download endpoint)
- https://icons.popclip.app/icon?cache=a2&specifier=… (icon render service)

GitHub (primary source repo — real manifests):
- https://github.com/pilotmoon/PopClip-Extensions (README: `source` vs `contrib`, curation policy, publication criteria; MIT)
- https://raw.githubusercontent.com/pilotmoon/PopClip-Extensions/…/source/Say…/Config.yaml (real shell-script + options)
- https://raw.githubusercontent.com/pilotmoon/PopClip-Extensions/…/source/AlternatingCase.popclipext/Config.js (real JS-module extension, options, import)

Release announcements (primary forum):
- https://forum.popclip.app/t/popclip-2026-7-released/3849 (2026.7: iCloud Sync, auto-update, folders/multiple-instances, Manage/Info sheets, version 2026.7.1, first paid update, min macOS 13.5)
- (older 2025.9 announcement: https://forum.popclip.app/t/popclip-2025-9-released/3544)

---

*Notation: claims marked [actions], [js-env], etc. map to the official spec-link lines above. Inferred
observations are labelled "inference" in the body. `docs/architecture`, `docs/developer-guide/package-format.md`,
and `docs/developer-guide/AGENTS.md` are the OpenClip-side references this document compares against.*