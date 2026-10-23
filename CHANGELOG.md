# OpenClip Changelog

All notable user-facing changes to OpenClip.

---

## Unreleased

- Clicking the AI Tools icon now opens its AI actions in your Actions order instead of the search popup ([#175](https://github.com/ganeshmshetty/openclip/issues/175)).

---

## v1.9.0 - 2026-10-20

- **Action sounds**: play a sound when any action finishes. Choose Click, Drop, Tink, Pop or your own file, and silence individual actions.
- **AI follow-ups as chat**, with undo and redo (⌘Z / ⇧⌘Z).
- **Per-action AI provider and model**, with self-updating cloud model lists.
- **Editable AI system prompt**, and a new AI tab in Settings ([#161](https://github.com/ganeshmshetty/openclip/pull/161)).
- **Smarter selections**: rich text is preserved, extensions can require detected content, and several selected links open at once.
- **oMLX preset** for local LLM servers.
- **Screen Recording permission** in Settings and a restyled onboarding.
- Fixed selection missing in Chrome, Ghostty and Electron apps.
- Fixed AI settings being lost across dev and release builds, and saved prompts being renamed when re-run.

### Contributors
- 🎉 First-time contributor: thanks to @entttom for making the AI system prompt editable ([#161](https://github.com/ganeshmshetty/openclip/pull/161))!

---

## v1.8.2 - 2026-10-12

### Features & Improvements
- **Removed modifier key triggers**: Reverted modifier key selection triggers to ensure 100% reliable popup appearance across all apps, restoring the direct "Appear Automatically" toggle.
- **OCR auto-copy setting**: Added a "Copy to Clipboard Automatically" setting under **General ▸ Shortcuts** with cursor status feedback.
- **Script action options in env**: Exposed custom script options to child processes via `OPENCLIP_OPTION_<NAME>`.
- **Popup paging & UI polish**: Added fit-to-width paging and refined count stepper in glass theme.

### Fixes & Stability
- **Fixed JS extension memory leaks (#46, #47)**: Prevented the fetch bridge from retaining `JSContext` and per-run `URLSession` instances.
- **Calculator bounds & safety (#50)**: Bounded recursion depth in `MathEvaluator` and safely rejected overflowing inputs.
- **AI stream cancellation (#43)**: Correctly surfaced stream cancellations for Cloud and Local AI actions.
- **AI key persistence (#42)**: Prevented recursion on API key save failures.
- **Classic card shadow clipping**: Added rasterization padding to prevent shadow buffer clipping on promoted AppKit layers.
- **Toast placement & Spaces**: Fixed status toasts to prefer placement above cursor and bars, and enabled them across fullscreen Spaces.
- **Loading pill shadow**: Reserved insets to eliminate shadow clipping on cancellable loading pills.
- **Update reminders**: Added reliable menu bar update badges and reminders.

---

## v1.8.1 - 2026-10-09

### Features & Improvements
- **Automatic extension updates**: Store-installed extensions update at launch and every six hours while OpenClip is running. Control this with the new **About → Extension Updates → Automatically Update Extensions** toggle, enabled by default. Disabled extensions stay disabled, and developer and sideloaded packages are excluded.
- **Extension store improvements**: The New section uses first-publish dates, the store displays the full catalogue total, and search and update lifecycle handling are improved.
- **Task-focused AI prompts**: AI actions follow the selected task more closely, including translation, code fixes, and editing.
- **Simpler update preferences**: Software updates use the stable channel with streamlined About settings.
- Added Android emulators to the app exclusion filter and moved Ghostty to menu-based copy handling.

### Fixes & Stability
- Fixed group and AI Tools sub-bars failing to open when delayed SwiftUI hover events cancelled the opening timer. Hover tracking now uses a shared target-transition handler.
- Restored popup hover highlights, tooltips, and sub-bars over other apps' fullscreen Spaces.

### Contributors
Thanks to @deskangel for improving Ghostty copy handling and adding Android emulator exclusions!

---

## v1.8.0 - 2026-10-07

### Features & Improvements
- **Modifier-held selection triggers**: Trigger popup actions conditionally by holding modifier keys (⌘, ⌥, ⇧, ⌃, or fn) while making text selections, allowing quick contextual actions without cluttering normal text selection.
- **Standalone AI actions on popup bar**: Place custom AI actions directly on the main popup bar alongside standard actions for instant one-click access.
- **Command Palette toggle**: Choose whether to display the command palette (⌘) button at the end of the popup bar under **Customize → Behavior**, while retaining the keyboard shortcut (⌥⌘C).
- **Screen text capture (OCR)**: Draw a region on screen to capture text using ScreenCaptureKit; the selected text feeds directly into the popup action bar.
- **Direct extension bundle installation**: Support drag-and-drop and double-click installation of `.openclipext` bundles directly.
- **Contextual pill placement**: Choose automatic, left, or right placement for the contextual pill, defaulting to Auto.
- **Rule matching by process name and path**: Target apps without bundle identifiers using their process name or executable path.
- **Customize polish**: Inline renaming, AI preset deletion, and drag-and-drop polish in the action editor.
- **UI & accessibility polish**: Larger popup bar metrics with 15 pt labels, refined hover highlights, contextual action and command palette controls in Settings, polished button styling, and unified menu bar status layout.

### Fixes & Stability
- Hardened selection and clipboard delivery across macOS apps with correlated diagnostics.
- Improved popup eligibility in other apps' fullscreen Spaces. A popup detected outside the active Space now gets one fresh-panel recovery attempt while its source app remains frontmost.
- Restored AI group visibility and preset round trips so group membership behaves consistently.
- Reliable screen-capture crosshair cursor over the selection overlay.
- Updated OpenSelection to 2.15.3 to bound Accessibility inspection and menu traversal workers during stalled app responses.
- Retained trace-linked placement and recovery diagnostics while reducing routine selection log noise.
- Enhanced search palette layout, context indicators, and row interactions.

### Contributors
Thanks to @iiHawe, @deskangel, @md786-dotcom, and @vynexor for their contributions to this release! ([#128](https://github.com/ganeshmshetty/openclip/pull/128), [#134](https://github.com/ganeshmshetty/openclip/pull/134), [#135](https://github.com/ganeshmshetty/openclip/pull/135), [#138](https://github.com/ganeshmshetty/openclip/pull/138), [#141](https://github.com/ganeshmshetty/openclip/pull/141), [#143](https://github.com/ganeshmshetty/openclip/pull/143))

---

## v1.8.0-beta.1 - 2026-10-03

### Features & Improvements
- **Modifier-held selection triggers**: Trigger popup actions conditionally by holding modifier keys (⌘, ⌥, ⇧, ⌃, or fn) while making text selections, allowing quick contextual actions without cluttering normal text selection.
- **Standalone AI actions on popup bar**: Place custom AI actions directly on the main popup bar alongside standard actions for instant one-click access.
- **Command Palette toggle**: Choose whether to display the command palette (⌘) button at the end of the popup bar under **Customize → Behavior**, while retaining the keyboard shortcut (⌥⌘C).
- **Screen text capture (OCR)**: Draw a region on screen to capture text using ScreenCaptureKit; the selected text feeds directly into the popup action bar.
- **Direct extension bundle installation**: Support drag-and-drop and double-click installation of `.openclipext` bundles directly.
- **UI & accessibility polish**: Refined contextual action and command palette controls in Settings, polished button styling, and unified menu bar status layout.

### Fixes & Stability
- Hardened selection and clipboard delivery across macOS apps with correlated diagnostics.
- Enhanced search palette layout, context indicators, and row interactions.

### Contributors
Thanks to @iiHawe for their contributions to this release! ([#134](https://github.com/ganeshmshetty/openclip/pull/134), [#135](https://github.com/ganeshmshetty/openclip/pull/135))

---

## v1.7.3 - 2026-10-02

### Features & Improvements
- **Popup controls**: Refined search and result-card buttons with compact spacing, consistent corners, and native Liquid Glass controls on macOS 26 when using the glass theme. Removed the search footer's action count.
- **Draggable search**: Move the search palette by dragging its search icon or header edges; the action bar retains the new position when leaving search.
- **Action editor**: Colored outline icons for appearance, triggers, and output settings, with descriptions available through hover-revealed info popovers.
- **Collapsible preferences sidebar**: Actions and Installed sections remember their expanded state. Searching reveals matching entries automatically.
- **Update release notes**: The About tab shows notes in a dedicated popover with support for Markdown, HTML, and plain text.

### Fixes & Stability
- Fixed action and extension ordering across reloads and availability changes, and improved toggle updates and group enablement in Preferences.
- Fixed removing a duplicated extension accidentally removing its original package.
- Improved global action hotkey selection capture, copy fallback, and trigger checks.
- Improved cloud AI model fetching when editing credentials or leaving its settings page.
- Corrected Sparkle's install-on-quit delegate callback and replaced deprecated browser-opening APIs.
- Updated OpenSelection to v2.15.1, with cursor-buffer safety and stricter AX inspection concurrency limits.

### Developer Tooling
- Debug builds now use a separate OpenClip Dev identity, with Accessibility recovery targeting the running app.
- Development runs show structured build, install, and launch progress, with grouped warnings and `--verbose` for complete output.
- Tests show progress grouped by test class, concise results, and relevant failures; `--verbose` provides the full log.

---

## v1.7.2 - 2026-09-30

### Features & Improvements
- **Popup pagination**: Choose how many actions appear per page, from 2 to 12; the contextual action island no longer reduces the main bar's page size.
- **Extension Store**: Browse the catalog as **All**, **Popular**, or **New**. New releases can also appear in the Featured showcase, and updates fill out the New preview when needed.
- **Selection reliability**: Hardened selection and inline-result capture with editability checks, shared gesture guards, and richer diagnostics in OpenClip's logs. OpenClip now uses OpenSelection 2.15.0; this is a dependency update, not an OpenSelection release.
- **Accessibility permissions**: Opening Accessibility settings no longer resets macOS permission state. TCC reset is reserved for the explicit recovery action.
- **Appearance preview**: The popup preview keeps a stable viewport as its width and page size change, and its sample icons stay independent of personal action customizations.

### Fixes & Stability
- Fixed action and extension enablement staying out of sync between the editor and toolbar.
- Fixed selection action icons when the popup is configured to show action titles as text.
- Fixed settings window width feedback from the Actions outline view.
- Improved selection safety around window gestures, weak Accessibility evidence, and inline results.

---

## v1.7.1 - 2026-09-28

### Fixes & Improvements
- **Sequence execution**: Multi-step action sequences now run deterministically item-by-item, preserving delivery feedback and paste intent (by @md786-dotcom in [#103](https://github.com/ganeshmshetty/openclip/pull/103)).
- **AI Bar Button**: Fixed AI launcher position retention and ordering across app restarts (by @vynexor in [#120](https://github.com/ganeshmshetty/openclip/pull/120)).
- **Extensions**: Safely allows `nativeFetch` to connect to local development servers on localhost with system port protection ([#122](https://github.com/ganeshmshetty/openclip/pull/122)).
- **Preferences**: Added drag-and-drop reordering for actions within custom groups.

### Contributors
Thanks to @md786-dotcom and @vynexor for their contributions to this release!

---

## v1.7.0 - 2026-09-27

### Contextual actions
- **The popup knows what you selected.** Actions with detection rules — math, links, dates, paths, and definitions — surface first on a matching selection, in their own island. Toggle prioritization per action in Preferences › Contextual Actions.
- **Inline file previews** in the popup: images, PDFs, and text render in place, with Quick Look for audio/video/office files.

### Build actions with AI
- **Describe an action and get a working one.** The builder now handles chatty model output, infers async automatically, validates JavaScript syntax inline, and never picks an icon that doesn't exist.

### Interface
- **The Clip Store**: new branding, and first-release extensions listed under **New**.
- **Settings rebuilt with Liquid Glass**: borderless sidebar, capsule search, colored tiles, and in-window shortcut recording.
- **Define**: one display picker — result card, Look Up popover, or Dictionary app.
- Better embedded PDF previews; the appearance preview renders your desktop wallpaper.

### Fixes
- Async JavaScript exceptions surface immediately instead of hanging (#48).
- Multi-click selections are no longer swallowed by the popup's first click.
- Mouse utilities (Mac Mouse Fix, HazeOver, NotchNook), screen-capture tools (CleanShot, Shottr, Snagit), and fullscreen apps no longer suppress the copy fallback in the app underneath.
- URL actions open in the frontmost browser window (#112); Ollama reasoning models skip the thinking pass (#115); WeChat selections supported; hold-to-paste anchors to the element under the press.

### Licensing
- **OpenClip is now AGPL-3.0** (was MIT). Copies obtained under MIT remain MIT. See NOTICE.md.

---
## v1.6.2 - 2026-09-20

### Features & Improvements
- **Native file output and interactive preview card**: JavaScript actions, shell scripts, and extensions can return files via `ActionResult.file`, `ActionResult.copyFile`, or `ActionResult.saveFile`, with interactive preview cards, Quick Look, drag-and-drop, and configurable save location.
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
- Join our [Discord community](https://discord.gg/acYYdzM7jR).

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
