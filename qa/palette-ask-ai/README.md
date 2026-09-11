# QA: Ask AI from the search palette (empty state)

Branch `feat/palette-ask-ai`. Recorded on 2026-09-11 against a Debug build of this branch
(Developer ID signed so the Accessibility grant applies), macOS 26.6, light appearance, Classic
theme, AI provider = Cloud API (OpenRouter, `openai/gpt-5.6-luna`). The editor is TextEdit with a
plain-text sample; the selection is the whole sentence (⌘A), the palette is opened with the bar's
⌘ button. Input was driven by a small CGEvent script so the timing is uniform; nothing in the app
was mocked — the AI responses are real.

## Videos

Each recording also has a `.gif` twin (10 fps, 720 px) so it plays inline on GitHub; the `.mp4` is the full-quality version.

| File | What it shows |
| --- | --- |
| `ask-ai.mp4` (19 s) | Select text → ⌘ → type `rewrite to slovak` (no action matches) → the empty state offers **Ask AI: “rewrite to slovak”** ⌘1 and **Save as AI tool** ⌘2 → ⌘1 → "Generating…" toast → result card titled *Rewrite to slovak* with the Slovak text, Copy / Paste. |
| `save-as-ai-tool.mp4` (19 s) | Same entry with `make it sound friendly` → ⌘2 → toast reads **Saved as AI tool · Generating…** → result card titled *Make it sound friendly* (diff view, since it is a light edit). |
| `reuse-saved-tool.mp4` (19 s) | Next selection → ⌘ → type `friendly` → the saved tool is now an ordinary palette result (sparkle icon, ⌘1) → ⌘1 runs it → result card. |

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-no-match-offers-ask-ai-and-save.png` | The empty state: two runnable rows instead of "No matches for …". |
| 2 | `02-ask-ai-generating-toast.png` | After ⌘1: the popup closes and the standard loading toast shows. |
| 3 | `03-ask-ai-result-card.png` | The streamed answer in the normal result card; the header is the instruction, capitalised. |
| 4 | `04-save-as-ai-tool-row.png` | Second row selected by ⌘2 (same rows, different query). |
| 5 | `05-saved-as-ai-tool-toast.png` | The save path's toast: "Saved as AI tool · Generating…". |
| 6 | `06-saved-tool-result-card.png` | The saved tool's first run; the card carries the tool's title and the diff toggle. |
| 7 | `07-saved-tool-is-a-palette-result.png` | On the next palette entry the tool matches by name like any preset. |
| 8 | `08-saved-tool-rerun-result-card.png` | Running it from its row. |

## Also verified

- **AI switched off** (`aiEnabled` = false): a non-matching query keeps the previous "No matches
  for …" copy, no AI rows — screenshot `09-ai-off-keeps-no-matches.png`; `PaletteAIPromptTests`
  pins that nothing runs on ⌘1 in that state.
- **A matching query still lists actions** — the reuse recording (`friendly` → the saved tool)
  and `testAMatchingQueryStillRunsTheActionNotAI`. The AI rows appear only when the result list
  is empty.
- **Keyboard paths** — Return, ⌘1 and ⌘2 on the rows are driven through the real palette in
  `PaletteAIPromptTests` (typed via the field editor, keys via `performKeyEquivalent`); the
  recordings use ⌘1/⌘2.
- **Saving twice** reuses the existing tool instead of creating a duplicate
  (`AIServiceManager.preset(matchingPrompt:)`, unit-tested; the toast then reads just
  "Generating…"). Not exercised in the recordings.
- **Light appearance** is what the recordings show (black text on the light card). Dark uses the
  same theme tokens as the ordinary result rows and was not recorded.

## Not covered here

- The saved tool's row under Preferences › Actions › AI Tools › Actions (rename / edit prompt /
  delete). It is created with the same `custom_` preset shape as the "Add Custom AI Action"
  sheet (`AIServiceManager.makeCustomPreset`, unit-tested), so it lists there like any custom
  preset, but no screenshot was taken.
- Browser-redirect provider: the instruction is handed to the browser template like a preset;
  no card. Not recorded.
