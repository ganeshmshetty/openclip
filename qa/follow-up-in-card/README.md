# QA: follow-ups refine the result card in place

Branch `feat/follow-up-in-card` (stacked on `feat/palette-ask-ai`, #85). Captured 2026-09-11 on a
Developer-ID-signed Debug build, macOS 26.6, light appearance, Classic theme, AI provider = Cloud
API (OpenRouter). TextEdit with a plain-text sample; the whole sentence selected with ⌘A; the
palette opened with the bar's ⌘ button; keys posted by a small CGEvent script. AI responses are
real. Only the follow-up behaviour changed in this branch; everything else is #85.

## Video

`follow-up-stays-in-card.mp4` (40 s; `.gif` twin plays inline on GitHub): ⏎ opens the card →
`shorter` ⏎ → **the card stays put**: spinner and "Refining…" in the field, the previous answer
visible until the first chunk, the new answer streaming into the same card at the same size, the
diff once it settles → `add a greeting at the start` ⏎ → **Esc
cancels** the refinement and the previous answer stays → Esc closes.

## Screenshots

| # | File | Moment |
| --- | --- | --- |
| 1 | `01-card-with-answer.png` | The first answer (⏎ path), follow-up field focused. |
| 2 | `02-refining-in-place-spinner-previous-answer-dimmed.png` | `shorter` ⏎: no hide, no toast — the header already reads "Shorter", the field shows the spinner and "Refining…", the answer streams into the same card. |
| 3 | `03-new-answer-streaming-into-the-same-card.png` | Mid-stream: identical card width and height to #1 (the size is frozen for the refinement). |
| 4 | `04-settled-with-diff-against-previous-answer.png` | Settled, the field back to "Follow up…" and focused. (Captured when the diff base was the previous answer; the base is now always the original selection, so this diff would show the net change from the selected text.) |
| 5 | `05-second-follow-up-refining.png` | A second follow-up in flight: the previous answer dimmed under the spinner. |
| 6 | `06-esc-cancelled-previous-answer-kept.png` | Esc during the refinement: cancelled, the previous answer and its title are back; the card is still open. |

## Also verified

- Card size: the width and height in #2, #3 and #4 match #1 exactly (the first live run of this
  branch showed the card re-measuring on every chunk; `freezeCardSizeForRefinement` pins the size
  from the moment ⏎ is pressed, unit-tested in `FollowUpInCardTests`).
- Esc cancel: the first live run showed Esc doing nothing while refining because the disabled
  field had dropped first responder; the field now stays enabled (⏎ is a no-op meanwhile) and the
  log shows "Follow-up cancelled in the result card" for #6.
- `FollowUpInCardTests` (7) drive the controller with a hand-fed stream: no mode change and no
  loading toast, previous answer until the first chunk, settle with the right title and diff
  base, cancel keeps the previous answer and ignores late chunks, failure restores it under an
  error toast, leaving the card drops the stream, the size freeze and its exceptions.

## Not covered here

- A failing provider mid-refinement (unit-tested only); dark appearance.
