# OpenClip Launch Todo

Flat, independently implementable checklist. Each item is self-contained; no item depends on another.

## Phase 1 — Ship-stoppers

- [x] Add `console.log` shim in `OpenClipJSHost` routed to `Log.js` (console.log currently throws ReferenceError and breaks actions)
- [x] Request notification authorization at first `notify` effect and surface denial via status (`ActionResultHandler.swift`)
- [ ] Fix `.paste` clipboard restore race: re-check change count before restoring; serialize restore per effect (`ActionResultHandler.swift`)
- [ ] Add trust/privilege confirmation dialog to store install path (`ExtensionCardView.swift`), matching the deep-link NSAlert
- [ ] Preserve manifest `version` + `capabilities` through `EditActionSheet` save (currently stripped)
- [ ] Call `KeychainActionOptionStore.clearValue` on uninstall to purge option values + secrets; prune orphaned `actionOrder` entries
- [ ] Surface extension load failures in Preferences (Installed list) using already-computed `ManifestValidationRecord.issues`
- [ ] Fix `MacTextRetriever.swift:244/266` unguarded `as! AXValue` casts (crash on misbehaving AX target)
- [x] Add `set -o pipefail` to `scripts/test.sh` (failing suite can currently exit 0)
- [x] Replace hardcoded `/Users/ganesh/...` in `scripts/dev_run.sh` with relative/DerivedData discovery
- [x] Add LICENSE (MIT or GPL-3.0) — required for open-source launch
- [x] Fix README: remove `.dmg` claim (zip only), correct "Xcode 15+" → Xcode 16+ for Swift 6
- [x] Fix `hasCompletedOnboarding` raw `UserDefaults.standard` access → `SettingKey`/`SettingsStore`
- [ ] Zip-slip fix: validate zip entries for containment *before* extraction (`ExtensionManager.swift`)
- [ ] Escape/`urlEncode` AppleScript `{text}` interpolation in `AppleScriptAction` (raw selection injected into script source)
- [ ] Add macOS notification permission request to onboarding or first `notify` use (see notify item)
- [ ] Surface AI "no provider/no result" as error banner instead of echoing input (`PopupView.swift runAIPreset`)
- [x] Fix onboarding ✕ path: set `hasCompletedOnboarding` on dismiss so wizard doesn't re-appear every launch
- [ ] Show Accessibility-denied banner/status-menu warning after onboarding (app is currently silently dead without AX)

## Phase 2 — Platform power

- [ ] Add `openclip.storage.get/set/remove` persistent KV store (JSON-typed) for JS + canvas, namespaced `extension.<packageID>.storage.*` via `SettingsStore`
- [ ] Install fetch polyfill + real async branch in `JavaScriptCanvasEngine` so canvas handlers can `await fetch(...)` (branch on `request.isAsync`)
- [ ] Add bounded timer primitive for canvases (`openclip.tick` / `setInterval`) with session-teardown cleanup and watchdog budget
- [ ] Add mid-flight re-render path so a long async handler can push progress ("Loading…" → result)
- [ ] Extend requirement vocabulary: `cut`/`paste`/`formatting`/`urls`/`path`, `!` negation, `option-x=y` value gating
- [ ] Expose regex capture groups + matched-vs-full text in JS bridge (`openclip.input.captures` exists; add matched/full distinction + array API)
- [ ] Populate `ActionContext.modifiers` from event monitor and expose as `openclip.input.modifiers`
- [ ] Add `openclip.readClipboard()` (NSPasteboard read, off JS thread)
- [ ] Add `openclip.readPackageFile(path)` with strict package-directory containment
- [ ] Deliver typed option values (bool/number/string) in `openclip.options` instead of strings-only
- [ ] Add `openclip.runShortcut(name, input)` input override to non-canvas host (canvas already has it)
- [ ] Make `.sequence` await each effect (incl. pasteboard restore) before next; add conditional/error short-circuit
- [ ] Add `pasteWithoutReplacing` (insert at cursor) + `pastePlain` + `duplicateSelection` effects
- [ ] Make `.cut` and `.keyPress` failures visible (no silent no-ops on unknown keys/bad contexts)
- [ ] Harden `deliverKeyboardEffect` activation race (retry/backoff, `postToPid` fallback) (`PopupWindowController.swift`)
- [ ] Wire `NSPerformService(serviceName)` for real `service` kind; fall back to picker when unnamed
- [ ] Add `cut`, `keyPress`, `runShortcut`, `notify`, `sequence`, `fail` types to shell JSON protocol (`ShellResultMapper`)
- [ ] Add per-action timeout override (manifest `"timeout"`, clamped) + per-request fetch timeout/AbortController
- [ ] Add handler error isolation in canvas: inline error node instead of session collapse (mount errors still collapse)
- [ ] Add canvas components: `select` (dropdown), `checkbox`, `progress`, markdown text
- [ ] Add `console` availability note to `docs/developer-guide/AGENTS.md` §7 and document string-typed option values
- [ ] Add "Debugging" box to author guide §10: `OpenClip --dump-logs --category=extensions --level=error`

## Phase 3 — Ecosystem plumbing

- [ ] Add `version` field to app `ExtensionItem` model (store serves it; app drops it today)
- [ ] Track installed version per identifier; compare vs catalog → "Update available" badge on store card
- [ ] Add in-app extension detail view (actions, options, version, author) + `openclip://store/<id>` deep link
- [ ] Add version-aware reinstall: compare versions, warn on same/older before destructive overwrite
- [ ] Add author submission path: `owner`/`sources` field in catalog, review gate, real reverse-DNS identifier in `new_extension.sh` (not `com.example.*`)
- [ ] Add authorURL/homepage to catalog schema + card footer link
- [ ] Derive store categories from server results (app hardcodes 6; server is free-form)
- [ ] Add `minOS` to catalog and fix web detail page hardcoded "macOS 12.0+"
- [ ] Validate icons in catalog build (SF Symbol existence or packaged image)
- [ ] Surface builtin/extension ID conflicts (reserved `builtin.` prefix, warn instead of silent replace)
- [ ] Add CI workflow (`.github/workflows/ci.yml`): xcodegen → test with `-resultBundlePath` artifact, submodules recursive
- [ ] Add release workflow (`.github/workflows/release.yml`): Developer ID signing + notarize + attach zip on tag
- [ ] Add universal binary (`arm64 x86_64`) to `package_app.sh`
- [ ] Add version bump automation (agvtool or script) — single source for `Info.plist` version/build
- [ ] Add "Check for Updates" (open releases URL) at minimum; consider Sparkle with appcast
- [x] Write CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
- [ ] Add issue/PR templates + FUNDING.yml (`.github/`)
- [ ] Add README badges (CI status, license, tests)
- [ ] Clean worktree junk: `reference/`, `graphify-out/`, `.superpowers/`, `default.profraw`; gitignore + remove `.agents/`
- [ ] Move `web/` marketing site to its own repo (or top-level `website/`)
- [ ] Merge `feat/component-canvas-implementation` into `main`; push `Extensions/` submodule commit before tagging v0.1.0

## Phase 4 — Deferred (post-launch)

- [ ] Add `openclip.runCommand` (JS → subprocess) behind capability gate (`ManifestCapabilityGate`)
- [ ] Add dynamic action generation (population function) to JS API
- [ ] Add rich-text input capture (`html`/`rtf`) + `openclip.input.html/markdown/rtf`
- [ ] Add declarative `keyCombo(s)` per action with `wait N` and key-combo-target modes
- [ ] Add `before`/`after` pipeline incl. `preview-result` and `paste-plain`
- [ ] Add app install-guards (`checkInstalled` + `bundleIdentifiers` + install prompt)
- [ ] Add browser context (`browserUrl`/`browserTitle`) to bridge
- [ ] Add file/export effects (`writeFile`, `revealInFinder`, share sheet)
- [ ] Add viewer window / HUD / toast presentation for long results (beyond canvas caps)
- [ ] Add keyboard layout-aware keyPress (TIS-based) + `type(string)` effect + key repeat
- [ ] Add rich components: table/grid, tabs/segmented, slider, list sections
- [ ] Raise/parameterize canvas limits (512 nodes / 64 list items) with lazy/virtualized lists
- [ ] Add app/context info API (OpenClip version, screen geometry, frontmost app)
- [ ] Add options UI richness: `heading`, `multiline`, `allow other`, per-option icons, generated settings sheet
- [ ] Add re-trigger popup (`popclip-appear`-style) + `copy-selection` helper
- [ ] Add ratings/reviews/screenshots/donations/changelogs to store schema + UI
- [ ] Add update channels (beta/stable)
- [ ] Add interactive notifications (UNNotificationCategory actions)
- [ ] Apply `denyFormatting`/`assumePaste` app policies to extension paste behavior
- [ ] Add `showCanvas` declarative mount (dead `ActionResult` case)
- [ ] Add hot-reload size/content-hash check (mtime-preserving copies currently missed)
- [ ] Add in-app "Extensions log" panel (last N `Log.extensions` entries)

## Docs & polish (parallel anytime)

- [ ] Fix stale `@MainActor` claims for `OpenClipSnippetParser` in AGENTS.md, `docs/architecture/overview.md`, `docs/developer-guide/snippets.md`
- [ ] Fix `directory-structure.md` drift: `Sources/OpenClip/App/` empty, `Core/Extensions/` nesting, `ActionRequirements.swift` missing
- [ ] Fix stale `PopupContentView` reference in AGENTS.md canvas line
- [ ] Document hot reload in author guide §10 (docs understate: ~2s, not relaunch)
- [ ] Document chmod requirement for `script:` files (script-file actions throw "not executable")
- [ ] Add local icon asset guidance (≥512px PNG, name must match, silent fallback)
- [ ] Add snippet-vs-package decision table to `snippets.md`; note snippets bypass `ManifestValidator`
- [ ] Run docs worked examples (9a/9b/9c) through `ManifestValidator` in an XCTest
- [ ] Add `node --check` to `validate_extension.sh` for JS syntax errors
- [ ] Make validation error messages action-specific: `actions[1] (keypress): missing required field "keyPress"`
- [ ] Print hot-reload hint in `install_extension.sh` ("app reloads within ~2s if running")
- [ ] Set executable bit in `new_extension.sh` templates
- [ ] Add `TestIsolation.reset()` + `MemorySettingsStore` to `CanvasRendererTests` (writes real prefs domain)
- [ ] Fix AI provider/StatusBar/Hotkey/Onboarding test coverage gaps (zero tests today)
- [ ] Add "Update available" flow docs when Phase 3 versioning lands
- [ ] Update `docs/architecture/extensions.md` failure-surfacing section when load-failure UI lands
