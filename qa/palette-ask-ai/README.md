# QA: quick AI from the search palette

Branch `feat/palette-ask-ai`, after folding in the pieces picked from the alternative drafts
(#86 recents, #87 follow-up, #88 ⏎/⇧⏎). Captured 2026-09-11 on a Developer-ID-signed Debug build
of this branch, macOS 26.6, light appearance, Classic theme, AI provider = Cloud API (OpenRouter).
TextEdit with a plain-text sample; the whole sentence selected with ⌘A; the palette opened with
the bar's ⌘ button; keys posted by a small CGEvent script. AI responses are real.

## Videos

Each recording has a `.gif` twin (10 fps, 720 px) so it plays inline on GitHub; the `.mp4` is
the full-quality version.

| File | What it shows |
| --- | --- |
| `ask-ai-replace.mp4` (22 s) | Type `rewrite to slovak` (no action matches) → the Ask AI / Save rows and the ⏎/⇧⏎ hint → **⏎** → "Replacing…" → the selection is replaced in place, "Replaced with AI result". |
| `shift-return-card-and-follow-up.mp4` (34 s) | Type `make it sound friendly` → **⇧⏎** → "Generating…" → the result card with the **follow-up field** → type `shorter` → ⏎ → the card updates with a diff against the previous answer → Esc. |
| `recent-prompt-and-save.mp4` (38 s) | Type `slo` → the **recent prompt** `rewrite to slovak` is a row (clock icon) with Save under it → ⌘1 runs it and replaces the selection → next selection, type `make it casual` → **⌘2** saves it as an AI tool and replaces the selection. |

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-ask-and-save-rows-with-hint.png` | Nothing matches: **Ask AI: “…”** (⌘1), **Save as AI tool** (⌘2) and the hint "⏎ replace selection · ⇧⏎ show result". |
| 2 | `02-replacing-toast.png` | ⏎: the popup closes, "Replacing…" shows while AI answers (click it to cancel). |
| 3 | `03-selection-replaced-in-place.png` | The answer pasted over the selection — the document now reads in Slovak. No card. |
| 4 | `04-shift-return-generating-toast.png` | ⇧⏎ on another instruction: the standard "Generating…" toast. |
| 5 | `05-result-card-with-follow-up-field.png` | The answer in the result card (diff view for a light edit) with the **follow-up field** under it, focused. |
| 6 | `06-follow-up-typed.png` | `shorter` typed as a follow-up. |
| 7 | `07-refined-answer-with-diff.png` | ⏎: AI ran on the previous answer; the diff shows what the follow-up changed. |
| 8 | `08-recent-prompt-row-and-save.png` | `slo` finds the recent `rewrite to slovak` as a row; Save is offered under it. |
| 9 | `09-saved-as-tool-replacing-toast.png` | ⌘2 on a typed instruction: "Saved as AI tool · Replacing…". |
| 10 | `10-saved-tool-replaced-in-place.png` | …and the selection replaced by the new tool's answer. |
| 11 | `11-saved-tool-is-a-preset-row.png` | The saved tool is now a preset row (`Make it sound friendly`, sparkle icon); it has left the recents. |

## Also verified

- With AI off, a non-matching query keeps the previous "No matches for …" copy (unit-tested:
  nothing runs on ⌘1 in that state).
- A matching query still lists actions (`friendly` → the saved preset), and presets keep their
  existing behaviour (the result card).
- Keyboard paths — ⏎ replace, ⇧⏎ card, ⌘1/⌘2, recents by fragment — are driven through the real
  palette in `PaletteAIPromptTests`; the controller's replace / copy / card outcomes and the
  recents bookkeeping in `PaletteAIReplaceTests`; the card's ⏎ decision and the follow-up run in
  `ResultCardFollowUpTests`; the history rules in `AIPromptHistoryTests`.
- Saving the same instruction twice reuses the existing tool (`preset(matchingPrompt:)`).
- Light appearance is what the captures show; dark uses the same theme tokens.

## Not covered here

- The "Copied AI result" / "Copied — the app changed" downgrades (unit-tested only).
- Preferences › AI › Actions listing of the saved tool (same custom-preset shape as the Add sheet).
- Browser-redirect provider (no card, nothing to paste).
