# OpenClip Launch Todo

Flat, independently implementable checklist. Each item is self-contained; no item depends on another.

## Phase 1 — Ship-stoppers

- [x] Add `console.log` shim in `OpenClipJSHost` routed to `Log.js` (console.log currently throws ReferenceError and breaks actions)
- [x] Request notification authorization at first `notify` effect and surface denial via status (`ActionResultHandler.swift`)
- [x] Fix `.paste` clipboard restore race: re-check change count before restoring; serialize restore per effect (`ActionResultHandler.swift`)
- [ ] Add trust/privilege confirmation dialog to store install path (`ExtensionCardView.swift`), matching the deep-link NSAlert
- [x] Preserve manifest `version` + `capabilities` through `EditActionSheet` save (currently stripped)
- [x] Call `KeychainActionOptionStore.clearValue` on uninstall to purge option values + secrets; prune orphaned `actionOrder` entries
- [ ] Surface extension load failures in Preferences (Installed list) using already-computed `ManifestValidationRecord.issues`
- [x] Fix `MacTextRetriever.swift:244/266` unguarded `as! AXValue` casts (crash on misbehaving AX target)
- [x] Add `set -o pipefail` to `scripts/test.sh` (failing suite can currently exit 0)
- [x] Replace hardcoded `/Users/ganesh/...` in `scripts/dev_run.sh` with relative/DerivedData discovery
- [x] Add LICENSE (MIT or GPL-3.0) — required for open-source launch
- [x] Package both `.zip` and `.dmg` assets, correct "Xcode 15+" → Xcode 16+ for Swift 6
- [x] Fix `hasCompletedOnboarding` raw `UserDefaults.standard` access → `SettingKey`/`SettingsStore`
- [x] Zip-slip fix: validate zip entries for containment *before* extraction (`ExtensionManager.swift`)
- [x] Escape/`urlEncode` AppleScript `{text}` interpolation in `AppleScriptAction` (raw selection injected into script source)
- [x] Add macOS notification permission request to onboarding or first `notify` use (see notify item)
- [ ] Surface AI "no provider/no result" as error banner instead of echoing input (`PopupView.swift runAIPreset`)
- [x] Fix onboarding ✕ path: set `hasCompletedOnboarding` on dismiss so wizard doesn't re-appear every launch

## Phase 2 — Platform power

- [ ] Add `openclip.storage.get/set/remove` persistent KV store (JSON-typed) for JS, namespaced `extension.<packageID>.storage.*` via `SettingsStore`
- [x] ~~Install fetch polyfill + real async branch in `JavaScriptCanvasEngine`~~ *(canvas engine removed)*
- [ ] ~~Add bounded timer primitive for canvases (`openclip.tick` / `setInterval`)~~ *(canvas removed)*
- [ ] Add mid-flight re-render path so a long async handler can push progress ("Loading…" → result)
- [x] Extend requirement vocabulary: `cut`/`paste`/`formatting`/`urls`/`path`, `!` negation, `option-x=y` value gating
- [x] Expose regex capture groups + matched-vs-full text in JS bridge (`openclip.input.captures` exists; add matched/full distinction + array API)
- [ ] Populate `ActionContext.modifiers` from event monitor and expose as `openclip.input.modifiers`
- [ ] Add `openclip.readClipboard()` (NSPasteboard read, off JS thread)
- [ ] Add `openclip.readPackageFile(path)` with strict package-directory containment
- [x] Deliver typed option values (bool/number/string) in `openclip.options` instead of strings-only
- [x] Add `openclip.runShortcut(name, input)` input override to the JS host
- [ ] Make `.sequence` await each effect (incl. pasteboard restore) before next; add conditional/error short-circuit
- [ ] Add `pasteWithoutReplacing` (insert at cursor) + `pastePlain` + `duplicateSelection` effects
- [ ] Make `.cut` and `.keyPress` failures visible (no silent no-ops on unknown keys/bad contexts)
- [ ] Harden `deliverKeyboardEffect` activation race (retry/backoff, `postToPid` fallback) (`PopupWindowController.swift`)
- [x] Wire `NSPerformService(serviceName)` for real `service` kind; fall back to picker when unnamed
- [x] Add `cut`, `keyPress`, `runShortcut`, `notify`, `sequence`, `fail` types to shell JSON protocol (`ShellResultMapper`)
- [ ] Add per-action timeout override (manifest `"timeout"`, clamped) + per-request fetch timeout/AbortController
- [ ] ~~Add handler error isolation in canvas: inline error node instead of session collapse~~ *(canvas removed)*
- [ ] ~~Add canvas components: `select` (dropdown), `checkbox`, `progress`, markdown text~~ *(canvas removed)*
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
- [x] Add CI workflow (`.github/workflows/ci.yml`): xcodegen → `./scripts/test.sh --unit` unit test runner, submodules recursive
- [x] Add release workflow (`.github/workflows/release.yml`): Xcode build + package zip & dmg + upload assets to GitHub Release on tag
- [x] Add DMG packaging (`OpenClip.dmg`) alongside `.zip` in `package_app.sh` with ad-hoc deep code-signing
- [ ] Add version bump automation (agvtool or script) — single source for `Info.plist` version/build
- [x] Add "Check for Updates" via Sparkle 2 framework (`UpdaterManager.swift` + `appcast.xml`)
- [x] Write CHANGELOG.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md
- [x] Add issue & PR templates (`.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/`)
- [ ] Add README badges (CI status, license, tests)
- [ ] Clean worktree junk: `reference/`, `graphify-out/`, `.superpowers/`, `default.profraw`; gitignore + remove `.agents/`
- [ ] Move `web/` marketing site to its own repo (or top-level `website/`)
- [x] ~~Merge `feat/component-canvas-implementation` into `main`~~ *(canvas removed)*; push `Extensions/` submodule commit before tagging v0.1.0

## Phase 4 — Deferred (post-launch)

- [ ] Add `openclip.runCommand` (JS → subprocess) behind capability gate (`ManifestCapabilityGate`)
- [ ] Add dynamic action generation (population function) to JS API
- [ ] Add rich-text input capture (`html`/`rtf`) + `openclip.input.html/markdown/rtf`
- [ ] Add declarative `keyCombo(s)` per action with `wait N` and key-combo-target modes
- [ ] Add `before`/`after` pipeline incl. `preview-result` and `paste-plain`
- [ ] Add app install-guards (`checkInstalled` + `bundleIdentifiers` + install prompt)
- [ ] Add browser context (`browserUrl`/`browserTitle`) to bridge
- [ ] Add file/export effects (`writeFile`, `revealInFinder`, share sheet)
- [ ] Add viewer window / HUD / toast presentation for long results
- [ ] Add keyboard layout-aware keyPress (TIS-based) + `type(string)` effect + key repeat
- [ ] Add rich components: table/grid, tabs/segmented, slider, list sections
- [ ] ~~Raise/parameterize canvas limits (512 nodes / 64 list items) with lazy/virtualized lists~~ *(canvas removed)*
- [ ] Add app/context info API (OpenClip version, screen geometry, frontmost app)
- [ ] Add options UI richness: `heading`, `multiline`, `allow other`, per-option icons, generated settings sheet
- [ ] Add re-trigger popup (`popclip-appear`-style) + `copy-selection` helper
- [ ] Add ratings/reviews/screenshots/donations/changelogs to store schema + UI
- [ ] Add update channels (beta/stable)
- [ ] Add interactive notifications (UNNotificationCategory actions)
- [ ] Apply app paste policies (`denyPaste`) to extension paste behavior (unified `PasteAvailability` currently covers built-in Paste/Cut + delivery)
- [x] ~~Add `showCanvas` declarative mount (dead `ActionResult` case)~~ *(showCanvas removed with the canvas feature)*
- [ ] Add hot-reload size/content-hash check (mtime-preserving copies currently missed)
- [ ] Add in-app "Extensions log" panel (last N `Log.extensions` entries)

## Docs & polish (parallel anytime)

- [ ] Fix stale `@MainActor` claims for `OpenClipSnippetParser` in AGENTS.md, `docs/architecture/overview.md`, `docs/developer-guide/snippets.md`
- [ ] Fix `directory-structure.md` drift: `Sources/OpenClip/App/` empty, `Core/Extensions/` nesting, `ActionRequirements.swift` missing
- [x] ~~Fix stale `PopupContentView` reference in AGENTS.md canvas line~~ *(canvas references removed from AGENTS.md)*
- [ ] Document hot reload in author guide §10 (docs understate: ~2s, not relaunch)
- [ ] Document chmod requirement for `script:` files (script-file actions throw "not executable")
- [ ] Add local icon asset guidance (≥512px PNG, name must match, silent fallback)
- [ ] Add snippet-vs-package decision table to `snippets.md`; note snippets bypass `ManifestValidator`
- [ ] Run docs worked examples (9a/9b/9c) through `ManifestValidator` in an XCTest
- [ ] Add `node --check` to `validate_extension.sh` for JS syntax errors
- [ ] Make validation error messages action-specific: `actions[1] (keypress): missing required field "keyPress"`
- [ ] Print hot-reload hint in `install_extension.sh` ("app reloads within ~2s if running")
- [ ] Set executable bit in `new_extension.sh` templates
- [x] ~~Add `TestIsolation.reset()` + `MemorySettingsStore` to `CanvasRendererTests` (writes real prefs domain)~~ *(canvas tests removed with the canvas feature)*
- [ ] Fix AI provider/StatusBar/Hotkey/Onboarding test coverage gaps (zero tests today)
- [ ] Add "Update available" flow docs when Phase 3 versioning lands
- [ ] Update `docs/architecture/extensions.md` failure-surfacing section when load-failure UI lands
