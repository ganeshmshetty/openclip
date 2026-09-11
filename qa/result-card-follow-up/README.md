# QA: follow-up field in the result card, and Ask… in AI Tools

Branch `feat/result-card-follow-up`. Screenshots taken 2026-09-11 on a Developer-ID-signed Debug
build of this branch, macOS 26.6, light appearance, Classic theme, AI provider = Cloud API
(OpenRouter). TextEdit with a plain-text sample; the whole sentence selected with ⌘A; input
driven by a small CGEvent script. AI responses are real. 

## Videos

Each recording also has a `.gif` twin (10 fps, 720 px) so it plays inline on GitHub; the `.mp4` is the full-quality version.

| File | What it shows |
| --- | --- |
| `ask-and-refine.mp4` (36 s) | Select → **AI Tools** → **Ask…** (⌘1) → the ask card → type `make it sound friendly` → ⏎ → answer with the follow-up field → type `shorter` → ⏎ → refined answer with the diff against the previous answer → Esc. |

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-ai-tools-leads-with-ask.png` | AI Tools opened from the bar: **Ask…** is the first entry (⌘1), the presets follow. |
| 2 | `02-ask-card-selection-and-field.png` | ⌘1: the ask card — the selection as a dimmed body, the instruction field focused ("What should AI do with this text?"), no Copy/Paste yet. |
| 3 | `03-first-instruction-typed.png` | `make it sound friendly` typed into the card. |
| 4 | `04-generating-toast.png` | ⏎: the standard "Generating…" toast. |
| 5 | `05-answer-with-follow-up-field.png` | The answer, titled after the instruction, with Copy/Paste and the field ready for a follow-up ("Follow up…"). |
| 6 | `06-follow-up-typed.png` | `shorter` typed as a follow-up. |
| 7 | `07-refining-toast.png` | ⏎ again: AI runs on the *current answer*. |
| 8 | `08-refined-answer-with-diff.png` | The refined answer; the diff toggle compares against the previous answer, not the original selection. |

## Also verified

- Two bugs found by this run and fixed before these captures: ⏎ in the field was reaching the
  source app (AppKit handles Return in an `NSTextField` before SwiftUI's key-press path, and the
  card's own ⏎ handler fired instead of the field's) — both paths now go through one decision
  (`ResultCardView.followUpReturn`, unit-tested); and the controller's focus nudge could land on
  the card's selectable body text instead of the field (now looks for the editable field only).
- `ResultCardFollowUpTests` covers the ⏎ decision table, the field's presence rules, the Ask
  entry's contract, `runFollowUp` running on the card text with the right title and diff base,
  and `runAISelection` opening the ask card / still running presets.

## Not covered here

- Esc / back-chevron behaviour on the ask card (unchanged card behaviour); dark appearance.
