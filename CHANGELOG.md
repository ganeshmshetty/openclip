# OpenClip Changelog

All notable user-facing changes to OpenClip.

---

## Unreleased

### Features & Improvements
- **Decision Tools (experimental)**: first-class peer to AI Tools for judging selections with typed answers (yes/no or a choice from a list you define) plus confidence — never paste generated essays. Preferences → **Decisions** configures Jev (TypeSafe System One) or the local Laya CLI; keys stay in SecretStore. Each tool can be given any icon the chooser offers. Decision tools nest under the **Decision Tools** row in Actions, like AI tools, and editing a tool shows its answer type.
- **Default Decision tools**: Smart action, Triage, Reply as…, Send to…, Safe to share?, Fix path, and bulk **Clean this list**.
- **Bulk decisions**: **Bulk…** is the last entry in the Decision Tools group and a palette row of its own. It opens a card that reports how many items the selection makes, lets you switch between **Row** and **Word** (the count follows), pick which decision to apply, and run it. Progress shows while it judges each item, results file into categories live — Yes / No / Unsure, or one per choice option — and you can copy any single category or all of them with headings.
- **Inline decision outcomes**: a Decision tool's icon spins while it runs, then turns into a green tick or red cross (yes/no), a grey question mark when the model is not confident enough, or, for a choice tool, the chosen label as plain text, in both the bar and the palette. Low confidence is never an error. The outcome fades back to the icon after 3 seconds and sits on a softly tinted button (bar) or row (palette) with a muted glyph. There is no card; bulk tools return their filtered list as ordinary text.
- **Laya runs locally**: Laya has no CLI, so OpenClip installs a Python environment under `~/.openclip/laya` (uv or python3, PyTorch, the `laya` package, about 1.5 GB with the model) and keeps a bundled bridge resident, so a decision is one forward pass on the Apple GPU. Settings → Decisions offers it in two steps — **Download** / **Delete** for the environment and model, **Start** / **Stop** for the running model — with an English or Multilingual checkpoint.
- **Quick Assist** (opt-in, off by default): with Live assist on, OpenClip reads the field you are typing in through Accessibility and answers the Decision tools you marked **Show in Quick Assist** in a small floating window you can drag anywhere (it opens bottom-right and remembers where you leave it). Every tool's question goes in one request, so a System One model answers them all in a single forward pass. The window shows the text it is judging: typing replaces it, **+** adds the current selection to it, the eraser clears it, and it clears itself 10 seconds after you stop typing. Yes/no tools show a tick, cross or question mark; choice tools show the chosen label. Password fields are never read and nothing is stored. The menu bar's **Live Assist** submenu turns it on for 30 minutes, an hour, or until tomorrow, like Pause, and **Always On** mirrors the Settings toggle.

---

## v1.6.2 - 2026-09-20

### Features & Improvements
- **Inbound `openclip://` automation API**: other apps can read and write a curated set of settings and run app-level commands (`open-settings`, `pause`, `resume`, `reset-appearance`).
- **Popup card chrome**: lit top rim, gradient hairline, and contact + ambient shadows; diff and pin controls hover-reveal.
- **Popup bottom fade**: content fades at the bottom edge instead of a material band; inset Actions-list separators.
- **Browser front-window opens**: browser-sourced URLs open through the browser's scripting, so private/incognito windows get a tab in the current window.
- **Define opens in Dictionary.app** from the result card.
- **Rich pasteboard fidelity**: copy and paste preserve every representation, including app-private types.
- **Inline results stay warm** across popups and repacks.
- **Actions list rework**: clearer rows, search, and drag-and-drop grouping; deleting a custom action removes it from its groups and clears its alias.
- **Hold-to-trigger** now works with **Appear Automatically** off.
- **Keyboard selection reads** without the copy-evidence gate.

### Fixes & Stability
- **Popup shadow**: no longer clipped, with the transparent ring derived from the shadow geometry.
- **Click intent**: resolved once per run, fixing right-click bleed and the wrong ⇧⏎ copy/paste outcome.
- **Log timestamps** format on the rotating file sink's own serial queue.
- **Settings**: sidebar search strip and last-pane restore.
- **Sub-bar results**: an in-flight inline evaluation is joined, not re-run.
- **Action editor**: option labels show as field prompts.
- **PowerPoint selection**: fixed via OpenSelection 0.2.3; KeyboardShortcuts 3.1.0.

### Held for a later release
- Native file output and interactive preview.

---

## v1.6.1 - 2026-09-16

### Features & Improvements
- **Apple Intelligence availability** is reported in Preferences › AI, with how to fix each state.
- **More reliable Apple Intelligence answers** via guided generation.
- **Inline results in sub-action bars** match the main bar.
- **Dependency update**: OpenSelection 0.1.2.

### Fixes & Stability
- **Overlay-safe selection reads**: no synthetic ⌘C while a foreign overlay owns the key window.
- **Result card stays on screen** as it resizes.
- **Empty-state hint** points custom actions to Actions.

---

## v1.6.0 - 2026-09-14

### First signed & notarized release
- **First genuinely signed, hardened, and notarized release** (app and DMG); every earlier build was ad-hoc and could not be notarized.
- **Re-grant Accessibility once** when upgrading from an ad-hoc build; Developer ID signing makes it survive future updates.
- **Fresh installs** open with no Gatekeeper warning.

### Features & Improvements
- **Settings rebuilt like System Settings**: one router, a searchable sidebar, and a page for every extension, built-in action, and custom action.
- **Ask AI from the palette**, including **Save as AI tool**; ⏎ shows the answer and ⇧⏎ replaces the selection.
- **Refine answers in the result card** with an inline follow-up, diffed against the original selection.
- **AI engines**: local CLIs and universal local models with automatic model resolution.
- **Duplication, pinning, and a sortable Store** with real publish dates.
- **Store**: sort options, publish dates, offline and update states, and **Install from File…**.
- **Result card and actions**: duplicate extensions and custom actions; pin button; frozen size while streaming; selection engine extracted to OpenSelection 0.1.1.

### Security & Distribution
- **Inside-out signing and notarization**: no `codesign --deep`; app and DMG are signed deepest-first, verified, and stapled, failing on any non-distributable artifact.

### Fixes & Stability
- Single-command extension pages render correctly and the hero scrolls with the page.
- Sidebar search has its own strip; the page switch no longer stretches; Store sort moved into the page.
- Follow-up keeps focus so Esc cancels; refinement never reopens a dismissed card.

### Contributors
- **Matej Bačo (@Meldiron)** — Developer ID signing, hardened runtime, and notarization; palette Ask AI; in-place result-card refinement; unified Settings window.
- **Ganesh M (@ganeshmshetty)** — AI CLI tools, universal local models, and model resolution; inline extension results.
- **JTOBIN (@binjto-boop)** — rebuilt the preferences window on stock AppKit controls.

---

## v1.5.0 - 2026-09-10

### Features & Improvements
- **Resizable result cards and search palette** with remembered maximum dimensions.
- **Per-action global hotkeys and search aliases.**
- **Extension group and sub-action reordering** via drag-and-drop, with custom member icons.
- **Universal binaries** (Apple Silicon + Intel) with verification across archives and DMGs.
- **In-app updater release notes** via Sparkle 2.9.
- **Redesigned DMG installer** with a branded, Retina background.
- **Custom icon importing** (SF Symbols, SVG, PNG).
- **Per-command extension settings** shown inline when options are declared.
- **Synchronous palette resolution and prewarming** to cut trigger latency.
- **Extension Store refresh button** and single-line descriptions.
- **Visual polish**: neutral selection highlights and capped toasts.

### Security & Distribution
- **Signed, hardened, and notarized builds** (app and DMG) open without a Gatekeeper warning.
- **Accessibility permission survives updates** with a Developer ID signature.
- **Minimal entitlements**: one exception for Apple events; the release scripts fail on any mismatch.

---

## v1.4.0 - 2026-09-07

### Features & Improvements
- **Visual before-and-after text diffs** in result cards.
- **Screen-space floating tooltips** that never clip.
- **Palette row keyboard shortcuts** (⌘1–⌘9 and alphanumeric).
- **Preferences and action-configuration fixes**, including editor persistence and Dock restore.
- **Process lifecycle cleanup** that kills descendant process trees.
- **Hardened AI presets** against prompt injection.

### Fixes & Stability
- Paste probe starvation recovery with aggregate deadlines.
- Zero idle CPU during toast dismissals.
- Selection permit released when `Edit ▸ Copy` is blocked.
- Hermetic, fully isolated test suite.

### Contributors
- **Matej Bačo (@Meldiron)** — action editor persistence; `dev_run.sh` improvements.
- **Jtobin (@binjto-boop)** — Settings window Dock restore.
- **Md (@md786-dotcom)** — descendant process termination; paste probe recovery.
- **Ganesh M (@ganeshmshetty)** — diff engine, tooltips, AI hardening, test refactor.

---

## v1.3.1 - 2026-09-05

### Features & Improvements
- **Direct action search** via shortcut, centered and focused, dismissed with Escape.
- **Search alignment clamping** within the bar and screen.
- **Layered glass contrast** with an adaptive scrim and specular borders.
- **Preferences label updates**: "Horizontal Position" and "Popup Width".

### Fixes & Stability
- **Extension Store resilience**: retries, loading states, and offline diagnostics.

---

## v1.3.0 - 2026-09-04

### Features & Improvements
- **`openclip.pasteboard` JavaScript API** for reading, inspecting, and writing clipboard content.
- **Customizable popup alignment and vertical position**, with synchronized sub-action bars.
- **Full multilingual localization**: Traditional Chinese, French, Japanese, plus multilingual search keywords.
- **Storefront and Actions overhaul**: category tabs, pagination, and drag-and-drop.
- **Snooze and per-app pause** from the status bar menu.

### Fixes & Stability
- Extension security: blocked path traversal and unauthorized script execution.
- Clipboard preservation for lazy pasteboard items.
- App-switch paste races; secret-staging permission race.
- Release notes in update prompts; settings preserved across updates.

### Community
- Join our [Discord community](https://discord.gg/sy4MeFxf8).

---

## v1.2.1 - 2026-09-02

### Features & Improvements
- **Context-aware web search** opens in the active browser.
- **Bar width slider** and dynamic page packing.
- **CLI flags** `--version`/`-v` and `--help`/`-h`.
- **Extension icon validation** in `validate_extension.sh`.

### Fixes & Stability
- Action group persistence across extension updates.
- Toast centered over the closed popup frame.
- Extension update failures logged and surfaced.
- Calendar `.ics` cleanup; safe `SettingsStore.get`; docs synced with Swift 6.

### Contributors
- **[@ayangweb](https://github.com/ayangweb)** — #26–#32.

---

## v1.2.0 - 2026-09-01

### Features & Improvements
- **Custom action groups and sub-action bar** with hovering sub-bar and scoped search.
- **Simplified Chinese localization.**
- **Search engine presets** (Google, DuckDuckGo, Kagi, Brave, Bing, Ecosia, Custom).
- **Sparkle 2 in-app updates** with background checks and release notes.
- **AI loading toast**, scaled toasts, and a menu bar icon toggle.

### Fixes & Stability
- Popup edge cursor stickiness and sub-bar hit-testing.
- AI session state across loading-toast transitions.
- Empty action groups can be created and configured.

### Contributors
- **[@ayangweb](https://github.com/ayangweb)** — #5, #12, #13.
- **[@cauton2020](https://github.com/cauton2020)** — #3.

---

## v1.1.1 - 2026-08-28

### Features & Improvements
- **Launch classification and permission recovery** for fresh installs, updates, and missing Accessibility.
- **Onboarding redesign**: 4-step wizard with recommended extensions and a live sandbox preview.
- **Reactive extension store** with instant install and remove.

### Fixes & Stability
- Reliable action reordering; correct "Copied" toast; simplified Homebrew install docs.

---

## v1.1.0 - 2026-08-26

### Features & Improvements
- **Anchored action configuration** popover with hero icon headers.
- **Unified result cards and live previews** across actions and AI tools.
- **Curated onboarding** with store recommendations.
- **Shared extension-store cache**, refined App Rules, and post-onboarding coach marks.

### Fixes & Stability
- Reliable cursor and selection detection via `NSCursor.currentSystem`.
- Clipboard fallback gated on I-beam cursors and paste probes.
- Popup shadow clicks fall through; toasts anchor cleanly.
- Catalog fixes across 25 extensions; validator accepts payload-free service actions.

---

## v1.0.1 - 2026-08-22

### Features & Improvements
- **Rich text**: capture and paste HTML/RTF with styles, headings, and links.
- **Mouse-hold trigger** with a configurable hold timer.
- **Expanded calendar providers**; normalized popup sizing across all 5 scale levels.

### Fixes & Stability
- No unexpected trust warnings while editing local extensions.
- Instant selection capture in Safari and Chromium browsers.

---

## v1.0.0 - 2026-08-21

The initial major release — a native floating action bar that turns selected text into instant actions.

### Highlights
- **Floating action bar**: contextual trigger, adaptive positioning, three themes, hover feedback, and clipboard fallback.
- **Built-in actions**: web search, calculator, dictionary, word completion, text transformations, and macOS Services/Share.
- **Search palette**: global **Option+Command+C** shortcut with recent-action ranking.
- **AI assistants**: Apple Intelligence, Ollama, OpenAI, or Anthropic, with streaming result cards and insert/replace.
- **Extensions**: in-app store, no-code custom actions, a 9,000+ icon library, and JavaScript / AppleScript / Shell / URL / Shortcuts runtimes.
- **Customization and privacy**: per-app rules, action reordering, 100% local operation, Keychain storage, subprocess isolation, and start at login.
