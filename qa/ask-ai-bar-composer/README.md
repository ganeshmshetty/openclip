# QA: Ask AI bar button with a prompt composer

Branch `feat/ask-ai-bar-composer`. Screenshots taken 2026-09-11 on a Developer-ID-signed Debug
build of this branch (so the Accessibility grant applies), macOS 26.6, light appearance, Classic
theme, AI provider = Cloud API (OpenRouter). TextEdit with a plain-text sample; the whole sentence
selected with ⌘A; input driven by a small CGEvent script. AI responses are real. 

## Videos

Each recording also has a `.gif` twin (10 fps, 720 px) so it plays inline on GitHub; the `.mp4` is the full-quality version.

| File | What it shows |
| --- | --- |
| `composer-ask.mp4` (24 s) | Select → **Ask AI** → type `rewrite to slovak` → ⏎ → "Generating…" → result card → Esc. |
| `composer-recents-and-save.mp4` (24 s) | Select → **Ask AI**: the recent instruction is listed → type `make it sound friendly` → **⇧⏎** → "Saved as AI tool · Generating…" → result card titled after the new tool. |

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-bar-with-ask-ai-button.png` | The bar with the new **Ask AI** button (speech bubble), next to AI Tools. |
| 2 | `02-composer-first-open.png` | Clicking it swaps the bar for the composer. First use: no recents, so the hint "Type what AI should do with the selected text". |
| 3 | `03-composer-typed-instruction.png` | `rewrite to slovak` typed: the **Ask AI: “…”** row (⌘1) and the footer hint "⏎ run · ⇧⏎ save as AI tool". |
| 4 | `04-generating-toast.png` | ⏎: the popup closes and the standard "Generating…" toast shows. |
| 5 | `05-result-card.png` | The answer in the normal result card, titled after the instruction. |
| 6 | `06-composer-lists-recent-prompt.png` | Next selection → Ask AI: the recent instruction is listed (clock icon, ⌘1) — reuse is one key. |
| 7 | `07-composer-new-instruction.png` | A different instruction typed; recents that don't contain it are filtered out. |
| 8 | `08-shift-return-saved-as-tool-toast.png` | ⇧⏎: "Saved as AI tool · Generating…". |
| 9 | `09-saved-tool-result-card.png` | The saved tool's first run; the card carries the tool's title (and the diff toggle for a light edit). |
| 10 | `10-composer-after-save-recent-removed.png` | The composer afterwards: the saved instruction has left the recents (it is a preset now); the other recent stays. |

## Also verified

- Esc from the composer returns to the bar; Esc again closes the popup.
- The saved tool is a regular custom preset: `PromptComposerTests` covers the preset factory,
  and it showed up as "Make it sound friendly" in the preset list (`aiActionPresetsJSON`) after
  the run; the recents key (`ai.recentPrompts`) held the remaining prompt.
- Keyboard paths (⏎ run, ⇧⏎ save, ⌘-digits on recents, Esc) are driven through the real view
  in `PromptComposerTests`.

## Not covered here

- Dark appearance (same theme tokens as the palette rows; not captured).
- The button's position in Preferences › Actions (it is an ordinary reorderable builtin row).
