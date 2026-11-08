# Typed Inline Results

Date: 2026-11-01
Status: Implemented (1.10.0). Current-state details and residual limitations live in `known-debt.md`.

## 1. Goal and scope

Extend automatic inline results from strings to two value types: **text and color**. Render them consistently in the main popup, group sub-bar, and search palette. Allow extensions to provide useful information without an executable interaction.

The design separates three decisions:

1. **Value:** what the extension returns.
2. **Presentation:** how OpenClip renders that value.
3. **Interaction:** whether activation delivers the value or does nothing.

A separate extension function is not a requirement. V1 reuses existing synchronous JavaScript entry points, with a restricted automatic-evaluation mode.

### Non-goals

- Arbitrary layouts, HTML, Markdown, SF Symbols, images, palettes, or embedded controls.
- Network-backed, asynchronous, shell, or AppleScript inline evaluation.
- A color picker, color editing, or automatic color Copy/Paste delivery; the result card may offer an explicit Copy of the hex and Save of the hex text.
- Different preview and click values, or independent click side effects for typed inline results.
- A new extension function, script file, or `inlinePreview` manifest key.
- Changes to unrelated non-inline actions or file output.

## 2. Baseline before this change (pre-1.10.0)

This section records the code as it stood when the design was written; sections 3–8 describe the
shipped 1.10.0 behavior.

- `Sources/OpenClip/Platform/Inline/InlineResultEvaluator.swift` prewarms, evaluates, caches, and publishes strings. Automatic evaluation calls the action implementation and accepts only nonblank `.text` results.
- `Sources/OpenClip/UI/Popup/PopupModeStore.swift` stores `[String: String]` results.
- `PopupView.swift`, `GroupSubActionBarView.swift`, and `PopupSearchView.swift` render strings separately. Activation can reuse a cached value or join an evaluation instead of rerunning the action.
- `PopupPageLayout.swift` calculates widths from preview text. The existing baseline content-width budgets are 172 pt in bars and 120 pt for search accessories.
- `Sources/Core/Extensions/Manifest/ExtensionOutputContract.swift` currently forces inline output to text, even when another output is declared.
- `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift` does not decode the proposed text/color objects. Existing returned file objects follow a different contract.
- `result: "preview"` already means delivery to the result card, not automatic inline display.

Returned effects are generally deferred, but filtering them after evaluation is not isolation: constructing a file result can already write a cache file. The new automatic path must restrict capabilities before executing any extension code.

## 3. Value contract

### Extension return values

```js
// Existing shorthand remains valid.
return "144";

// New typed values.
return { type: "text", value: "144" };
return { type: "color", value: "#FF8800" };

// No applicable result.
return null;
```

These objects contain data, not display instructions. There are no fonts, sizes, callbacks, nested visuals, copy values, or paste values.

| Type | Inline display | Supported delivery |
| --- | --- | --- |
| Text | One line; truncate visually if necessary | Paste, Copy, Show |
| Color | Small swatch plus canonical hex code | Show card; explicit Copy/Save in the card |

A swatch and its hex code constitute one color presentation, not a general mixed-content layout.

### Validation

- `value` must be a string. Do not stringify arbitrary structured objects, arrays, or booleans through the new typed decoder.
- Text preserves its exact value. Blank text is not an inline result. Collapse line breaks and tabs only in the inline display representation; Copy/Paste and Show use the original text.
- Emoji glyphs need no distinct type: any glyph is a valid text value, preserved and delivered verbatim.
- Color accepts only `#RGB`, `#RGBA`, `#RRGGBB`, and `#RRGGBBAA`, interpreted as sRGB. Expand shorthand and uppercase the canonical value. Use `#RRGGBB` when opaque and `#RRGGBBAA` otherwise. Do not accept CSS functions, named colors, gradients, or wide-gamut profiles in v1.
- The structured return type must match an explicitly declared inline output kind. A mismatch is invalid, not an invitation to reinterpret the value.
- Unknown fields are ignored. An unknown type or invalid value produces no automatic preview. Do not reinterpret malformed typed objects as text.
- Limit automatic text values to 64 KiB UTF-8 and colors to the accepted hex syntax. Display-only text has a tighter limit of 256 grapheme clusters and 4 KiB UTF-8 so its full value remains suitable for noninteractive inspection. Check bounds before caching, publishing, or measuring text. Reject oversized values rather than truncating the deliverable value.
- Decode only the known shallow fields under the execution budget. Cycles, throwing getters, or excessively large objects must not trigger recursive serialization or unbounded traversal.

Existing untyped JavaScript return coercion outside the new typed decoder remains unchanged. Large ordinary non-inline action outputs are not truncated by the inline limit. Inline invocation can obtain a text value too large to preview, but must not silently truncate or reinterpret it.

## 4. Manifest contract and compatibility

Keep `inline` Boolean-compatible. Add `displayOnly`, defaulting to `false`, and add the `color` output kind.

```json
{
  "type": "javascript",
  "inline": true,
  "displayOnly": false,
  "output": "color",
  "result": "preview"
}
```

An informational text action uses:

```json
{
  "type": "javascript",
  "inline": true,
  "displayOnly": true,
  "output": "text"
}
```

Rules:

- These are action-level fields on leaf actions, including group children. They are not inherited interaction settings for a structural group.
- `displayOnly: true` requires `inline: true` and a valid synchronous JavaScript action. Reject invalid combinations rather than silently creating a nonfunctional item.
- Keep the existing bans on async inline actions and inline rich-selection capture.
- Preserve an explicitly declared `color` output instead of overwriting it with text. Omitted output on legacy inline actions retains its existing text fallback.
- Text supports the existing `preview`, `paste`, `copy`, and `paste-or-copy` recommendations. Their default remains `paste-or-copy`.
- Color supports only `preview`. An incompatible recommendation produces a validation warning and falls back to `preview`, following the existing incompatible-pair policy.
- For display-only actions, delivery recommendations are inactive and delivery settings are hidden. A supplied recommendation may be retained but cannot activate delivery.
- New typed values and `displayOnly` require `minOpenClipVersion` at least equal to the release that introduces this feature. This is a release gate: older apps ignore unknown keys and must not be allowed to execute an informational item accidentally.
- Existing pure string-return scripts and `inline: true` continue working. Existing non-inline effects and returned-file objects retain their contracts. Inline invocation is deliberately value-only: legacy scripts that require effect APIs on click must remove `inline` and remain ordinary actions.

The authoritative extension specification and catalog live in the separate `Extensions/` repository. Updating their documentation, validator, and examples is coordinated follow-up work, not a change to this repository by implication.

## 5. Activation and delivery

### Interactive results: `displayOnly: false`

Activate the represented value, not an unrelated action effect.

1. Reuse a successful value from the current evaluation identity.
2. If evaluation is pending, join that same evaluation with its remaining budget.
3. If no usable preview exists, use the existing invocation coordinator to request a value, not unrestricted action execution. Keep the same capability restrictions as automatic evaluation, and accept only supported value results compatible with the declared output. Forbidden effect calls fail before performing the effect; explicit effects, files, sequences, and arbitrary results cannot bypass the value contract. A deliberate activation may start a fresh bounded evaluation when no usable evaluation is pending; this is not an automatic retry.
4. Validate the selection/session and destination before delivering. Never deliver an older selection's cached or late result.

For text, route delivery through the existing resolver rather than recreating click rules in each view:

- Primary defaults to paste, falling back to copy when paste is unavailable.
- Secondary defaults to copy.
- Preserve existing exceptions: primary Copy makes secondary Show; an explicit user Show preference keeps both clicks in Show.
- Existing recommendations and user overrides remain effective where supported.
- Existing source and destination restrictions remain authoritative for cached values, fresh evaluation, and card commands. In particular, OCR-derived text must not paste even when a destination accepts paste; a requested paste falls back to copy under the existing policy.
- Copy/Paste uses the complete text, never the truncated inline label.

For color, primary and secondary activation both Show the color result card. Unsupported copy/paste preferences cannot convert it into text delivery. Preserve its typed identity through card presentation.

Show keeps the popup in content mode. Text retains appropriate Copy/Paste controls. The color card displays the swatch and code and offers explicit Copy (canonical hex) and Save (plain-text hex) actions; these are deliberate card actions, not automatic delivery. It has no Paste action, no paste probe, and never writes the clipboard on show. ⌘C and ⏎ copy the hex; ⌘S saves it.

This capability restriction also applies to force-copy routes and automatic card commands. A cached color must never enter `.text` delivery merely because its canonical value is a string; the explicit card Copy is the only clipboard path.

### Informational results: `displayOnly: true`

`displayOnly` describes intent across mouse, keyboard, and search. It is not inferred from type, missing output, or a failed evaluation.

- Evaluate and display the inline value normally.
- Click, secondary click, Enter, and Shift-Enter do not invoke the action, deliver a value, open a card, dismiss the popup, or record an execution.
- Do not register execution hotkeys or offer execution shortcuts. Existing bindings must not bypass the policy.
- Keep the item searchable, readable by assistive technology, and eligible for normal enable/disable and configuration controls.
- A native hover tooltip reveals the full bounded text value, and the accessibility value exposes it without truncation. Keyboard selection in search exposes the same full value as noninteractive detail. This is inspection, not Show delivery: it does not execute, open a card, or dismiss the palette.
- Use normal readable content styling, not disabled opacity or a misleading actionable hover treatment.
- A failed or missing preview does not make the item executable.

Apply this guard at the shared invocation seam, including bound-action execution, not only in SwiftUI click handlers.

## 6. Search palette

Search remains an action/title list with a live value accessory, not a list whose titles change into computed values.

- Keep the configured icon/title on the left and typed result on the right.
- Use the same semantic renderer as the main and group bars, with the search surface's smaller size and width budget.
- Preserve indexing and ranking by existing action metadata. Do not index transient result values or let arrivals reorder results.
- Keep keyboard selection by stable action ID when results refresh.
- Interactive text rows use existing delivery on click/Enter. Color rows Show the card; their primary footer label is Show rather than Run.
- Display-only rows remain keyboard-selectable for inspection and accessibility. Activation does nothing. Replace execution footer controls with noninteractive informational detail containing the full bounded value, and expose its informational status accessibly.
- Display-only rows have no Command-digit hint. Preserve existing positional digit mapping for other rows; do not redirect a display-only row's digit to a neighboring action.
- Command must not hide a display-only preview merely to make room for a nonexistent execution hint.
- Apply the same restrictions to direct row clicks, footer controls, key equivalents, and custom hotkeys.

## 7. Evaluation, caching, and safety

Use the existing synchronous JavaScript dispatch in an explicit automatic-preview mode. No new extension function is required.

### Restricted automatic execution

- Create the restricted environment before top-level code or required modules execute.
- Supply the captured selection/match snapshot and required resolved options. Do not capture fresh clipboard data for automatic preview.
- Allow existing contained package-local helper modules, not arbitrary filesystem access.
- Do not expose fetch, clipboard read/write, file creation/output, URL opening, notifications, keypresses, subprocesses, or configuration effects.
- A forbidden operation fails the preview without performing the operation. Checking only the final returned result is insufficient.
- Retain trust/consent and required-option checks. Automatic evaluation cannot prompt for configuration or consent.
- Preview purity is an extension contract, not proof of isolation. JavaScript execution budgets do not provide a memory sandbox; do not claim protection against all allocation attacks.

### Lifecycle

- Keep the existing 0.90 s automatic-evaluation budget. Bound waiting for an execution slot as well as actual execution; use JavaScriptCore's VM limit for nonterminating synchronous code.
- Reject promises in this synchronous interface without waiting for them or leaking detached callbacks.
- Use bounded concurrency and deduplicate identical work. Prioritize visible rows/buttons over the offscreen catalog.
- Track pending, ready, not-applicable, failed, and cancelled outcomes separately. `null` and validation failures must not cause the existing generic retry loop to repeatedly run the same script. Do not automatically retry v1 evaluations within the same session.
- Cancel obsolete work on dismissal, selection replacement, option changes, extension reload, or removal. Reject stale completion and cache writes using the full request identity.
- If an item disappears or becomes disabled while evaluation is running, it cannot later deliver a value.

### Cache identity and bounds

- Default extension caches to session scope; time, randomness, and other JavaScript globals make persistent determinism unsafe to assume.
- Retain cross-session reuse only for proven pure built-ins such as Calculate.
- Identify requests by action identity/revision, exact relevant input snapshot, resolved match, and option revision. Include exposed locale/time-zone context when applicable. Do not use a text hash alone as equality.
- Store each evaluated value once and share it across surfaces. Cache not-applicable outcomes within the session.
- Retain a maximum of 200 entries and add a 1 MiB total cached-value budget. Evict entries to satisfy both bounds. Reuse the existing synchronous-JavaScript execution gate to bound in-flight execution; queue waiting remains part of the request budget.
- Do not persist selected text, options, or results. Log only identifiers, timings, and outcome categories through the existing Log interface; never log returned content or secrets.

## 8. Native presentation and architecture

Use a small platform-independent value contract, with text and normalized sRGB color variants. Preserve typed values through evaluation, delivery capability checks, and result-card presentation. Keep existing `.text` handling compatible rather than replacing unrelated action-result behavior.

Core may contain semantic values, output-kind validation, and delivery restrictions. Fonts, popup layout, swatch rendering, accessibility presentation, and preview lifecycle state belong in `Sources/OpenClip/`, not Core.

The implementation needs these focused changes:

| Area | Responsibility |
| --- | --- |
| Manifest/output contracts and factory | Decode `displayOnly`; preserve new output kinds; carry interaction policy |
| JavaScript host | Decode typed returns; enforce restricted automatic execution before loading code |
| Inline evaluator | Typed outcomes, bounded scheduling/cache, cancellation, and request identity |
| Popup state | Publish typed values rather than strings |
| Shared native renderer and layout metrics | Consistent bars/search rendering and measured width |
| Shared activation/delivery path | Guard display-only; preserve type-specific capabilities across entry points |
| Result card | Show colors without losing delivery restrictions |

Avoid a second renderer or executor for each result type. Do not introduce a general plugin-view framework.

### Layout and accessibility

- Host owns all sizing and styling. A swatch has a bounded visual slot; text consumes the remaining surface budget.
- Width calculation and rendering share the same rules, including swatch width, spacing, padding, and truncation.
- Transparent colors use a checkerboard background. White/black swatches retain an outline in both themes.
- A color's code remains readable independently of color perception. Announce the action title and value.
- Test CJK, RTL, mixed-direction text, unsupported glyphs, display scale, high contrast, reduced motion, and reduced transparency on macOS 14+.
- Preserve the selected/hovered action by ID when late previews alter page widths. Do not move a pressed target to another page during pointer activation.
- Recompute placement safely near screen edges and across displays. Preview arrivals must not change focus or activate the source application.

## 9. Acceptance and regression checks

Implementation is complete only when all of the following are demonstrated:

1. Legacy Calculate and string-return inline extensions retain expected text and delivery behavior.
2. Typed text and color render consistently in the main bar, group bar, and search palette.
3. Color values never enter automatic app-provided Copy/Paste delivery, including secondary, force-copy, keyboard, and result-card routes; the card's explicit Copy/Save are the only clipboard/file actions.
4. Text retains the current delivery preference matrix, paste fallback, OCR no-paste restriction, and exact untruncated output.
5. Display-only items cannot execute through mouse, footer, Enter/Shift-Enter, Command-digit, or bound-action paths; no execution history or dismissal occurs.
6. Search titles/ranking remain stable; informational previews remain visible with Command held and have no execution hints.
7. Existing successful/in-flight values are reused once per identity. Old selections and reloaded extensions cannot publish, cache, or deliver late values.
8. Null, blank, malformed, oversized, mismatched, unsupported, throwing, promise, and timed-out returns fall back safely without automatic repeated evaluation. Invocation after preview failure cannot execute forbidden effects.
9. Emoji glyphs returned as text, transparent colors, shorthand colors, multiline text, and RTL/CJK display have explicit tests.
10. Top-level code, module initialization, and result construction cannot perform forbidden preview effects, including cache-file writes or clipboard capture.
11. Infinite-loop evaluation releases its slot; queueing, concurrency, cache byte/entry limits, and cancellation are bounded.
12. Old-app minimum-version enforcement prevents unsupported informational/typed extensions from running on older versions.
13. Truncated display-only values can be inspected in full through hover, keyboard selection, and accessibility without execution or card delivery.

Start with focused manifest, host, evaluator, delivery, search-shortcut, and layout tests. Then run the full app test suite and build. Perform a manual keyboard/accessibility pass across all three surfaces and result cards.

When implementation changes current behavior, update `docs/architecture/known-debt.md`, runtime/developer documentation, and translated user-facing copy. Coordinate extension-author documentation and fixtures in the catalog repository.

## 10. Stop condition

Ship only the three value types, fixed native presentation, type-aware delivery, and explicit display-only behavior. Additional visuals, custom layouts, separate preview entry points, and independent click actions require a new design decision rather than being folded into this feature.
