# QA: Instant AI shortcut (replace the selection in place)

Branch `feat/instant-ai-hotkey`. Screenshots taken 2026-09-11 on a Developer-ID-signed Debug build
of this branch, macOS 26.6, light appearance, Classic theme, AI provider = Cloud API (OpenRouter).
TextEdit with a plain-text sample; the whole sentence selected with ⌘A; keys posted by a small
CGEvent script (the ⌥⌘I hotkey included). AI responses are real. 

## Videos

Each recording also has a `.gif` twin (10 fps, 720 px) so it plays inline on GitHub; the `.mp4` is the full-quality version.

| File | What it shows |
| --- | --- |
| `instant-replace.mp4` (22 s) | Select → **⌥⌘I** → type `rewrite to slovak` → ⏎ → "Replacing…" → the selection is replaced in place, "Replaced with AI result" toast. |
| `instant-review-path.mp4` (24 s) | Select → **⌥⌘I** → **↑** recalls the last instruction → **⇧⏎** → "Generating…" → the result card instead of an in-place replacement → Esc. |

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-instant-prompt-at-selection.png` | ⌥⌘I on the selection: the one-line prompt, nothing else. Hints: ⏎ replace selection · ⇧⏎ show result. |
| 2 | `02-instruction-typed.png` | `rewrite to slovak` typed. |
| 3 | `03-replacing-toast.png` | ⏎: the prompt closes, "Replacing…" shows while AI answers (click it to cancel). |
| 4 | `04-selection-replaced-in-place.png` | The answer pasted over the selection — the document now reads in Slovak. No card. (The "Replaced with AI result" toast had already faded by this frame; see the video.) |
| 5 | `05-up-arrow-recalls-last-prompt.png` | Next selection → ⌥⌘I → ↑ recalls the last instruction; the "↑ last prompt" hint appears once one exists. |
| 6 | `06-shift-return-generating-toast.png` | ⇧⏎: the review path — standard "Generating…" toast. |
| 7 | `07-shift-return-result-card.png` | …and the normal result card (Copy / Paste) instead of an in-place replacement. |
| 8 | `08-no-selection-toast.png` | ⌥⌘I with nothing selected: "Select some text first". |

## Also verified

- A first run of this flow with the bar dismissed beforehand resolved the *clipboard* fallback
  and pasted AI's answer for the clipboard text over the selection. That is now refused: Instant
  AI requires a live selection (`HotkeyManager.handleInstantAI`), which is what the screenshots
  above show. `InstantAITests` covers the keys, the scoping and both delivery outcomes (paste vs
  copy when the target can't paste or the app changed) with a recording result handler.
- The shortcut recorder sits under Preferences › General ("Instant AI Shortcut"); not captured.

## Not covered here

- Dark appearance; the "Copied — the app changed" downgrade (unit-tested only).
