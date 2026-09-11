# Floating Popup Panel Architecture

The floating popup panel subsystem presents contextual actions near the user's cursor or text selection. It consists of `PopupPanel` (an `NSPanel` subclass), static frame math in `PopupPositioner`, SwiftUI rendering in `PopupView`, and lifecycle coordination via `PopupWindowController`.

---

## Window Components

```
+-----------------------------------------------------------------------------+
| PopupWindowController |
| ├── PopupPanel (NSPanel, non-activating, borderless, popUpMenu level) |
| │ └── NSHostingView(PopupView) |
| │ ├── Action Buttons / Sub-menus |
| │ ├── ResultCardView (native result card in .content mode) |
| │ └── Status toast (floating `ToastPanelController`, outside the panel) |
| └── Event Monitors (Global / Local NSEvent tracking) |
+-----------------------------------------------------------------------------+
```

### 1. [`PopupPanel`](../../Sources/OpenClip/UI/Popup/PopupPanel.swift)
- **Base Class**: `NSPanel`
- **Window Style**: `.nonactivatingPanel`, `.borderless`
- **Window Level**: `.popUpMenu` (sits above all normal, floating, and status-bar windows; only system menus and the screen saver stack higher). The panel is deliberately **never** the key window by default; making it key would steal keyboard focus from the active app and swallow keystrokes. There are two scoped exceptions — action-search mode and content (AI-card) mode: `PopupPanel.allowsKey` gates `canBecomeKey`/`canBecomeMain`, enabled by `PopupWindowController.enterSearch()` and `enterKeyMode()` (search and content both route through the same `enterKeyMode()`/`exitKeyMode()` primitives).
- **Properties**: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` (SwiftUI draws its own shadow; a panel shadow causes double artifacts). `pinBottomEdgeOnResize` (search/content mode only) re-anchors content-driven growth — see *Action-Search Palette & Panel Growth* below.
- **Shadow inset**: `PopupView` keeps `PopupMetrics.popupShadowInset` (16pt) of SwiftUI padding around the bar and AI result card so the SwiftUI shadow renders *inside* the panel rather than being clipped at its edge. If a shadow looks cut off, increase the padding — never re-enable the panel shadow. That padding ring is fully transparent but still part of the window frame, which originally made shadow clicks do *nothing*: the panel was topmost at those pixels, the local event counted as "in the bar", and no app received the click. Two layers now handle it: (1) every click/right-click dismissal check uses `isOverPanelContent` (frame minus ring), so a press in the shadow always dismisses; (2) while the pointer hovers the ring, `updatePopupHover` sets `panel.ignoresMouseEvents = true`, so the click genuinely falls through to the app underneath and the global monitor observes it. The ignores-toggle requires global monitoring (Accessibility); without AX, layer 1 alone still guarantees dismissal, though the underlying app won't receive the swallowed ring click.

### 2. [`PopupWindowController`](../../Sources/OpenClip/UI/Popup/PopupWindowController.swift)
- **Responsibility**: Controls window creation, display lifecycle, event monitoring, hover tracking, and the popup mode state machine (actions bar ↔ search palette ↔ content/AI-card).
- **Event Handling**: Sets up local and global `NSEvent` monitors (`.leftMouseDown`, `.mouseMoved`, `.scrollWheel`, `.keyDown`). The local monitor sees mouse events over the panel; the global monitor sees events system-wide.
- **Dismissal Threshold**: Automatically dismisses the popup if the cursor moves beyond `PopupMetrics.popupDismissalDistance` (suspended in search mode and while a content/AI-card is open). For the result card, un-dragged cards dismiss normally on outside click or app switch; if dragged by the user (`hasUserMovedCard`), `cardIsModal` pins the card against outside clicks and document scrolls until Copy, Paste, Close or Esc (switching active applications or spaces still dismisses).
- **Keyboard Dismissal**: Requires Accessibility permission (the global monitor). In actions mode any key — including `Escape` — dismisses the popup; the global monitor is observation-only, so the keystroke still lands in the source app's document and the panel never needs to become key. In search mode the panel *is* key, so keys go to the search field (`Escape` clears a scoped query, then exits). In content mode the panel is *also* key: the AI result card owns all keys via SwiftUI `.onKeyPress`, `Escape` closes the card (`hide()`), and the controller monitor stays observation-only so it never double-fires Esc — bar the one case where the panel has lost key (the card outlives clicks into the source app document), where the monitor answers Esc itself.

---

## Hover Tracking & Preview Isolation

- **Shared hover state**: the real popup observes `PopupHoverState.shared`, a `@MainActor` `ObservableObject` (`location`, `usesGlobalMouseMonitoring`) fed by `PopupWindowController`'s global mouse monitor.
- **Injected, not hardcoded**: `PopupView` receives `hoverState: PopupHoverState = .shared` and `isStatic: Bool = false` in its initializer. When `isStatic` is `true`, `updateHoveredTarget`/`useLocalHoverFallback` early-return, so hover tracking is fully inert.
- **Static previews opt in**: [`PopupPreview`](../../Sources/OpenClip/UI/Popup/PopupPreview.swift) (Preferences Appearance tab + onboarding Finish) is a static visual with a fixed canonical action set; it passes its **own** `PopupHoverState()` and `isStatic: true` so hovering the preview never reacts to — or leaks into — the real popup's shared state.

---

## Positioning Math: [`PopupPositioner`](../../Sources/OpenClip/UI/Popup/PopupPositioner.swift)

`PopupPositioner` is a **pure static struct** with zero state or singletons. It calculates panel coordinates relative to the mouse release point and drag direction, preventing the panel from obscuring selected text.

### Calculation Rules

```swift
public static func placeNearReleasePoint(
 releasePoint: CGPoint,
 mouseDownPoint: CGPoint? = nil,
 popupSize: CGSize,
 screenBounds: CGRect
) -> CGRect
```

1. **Horizontal Alignment**:
 - Centers the popup horizontally over `releasePoint.x`:
 $$\text{x} = \text{releasePoint.x} - \frac{\text{popupSize.width}}{2}$$
 - Clamps $\text{x}$ within screen visible bounds with padding:
 $$\text{x} = \max(\text{minX} + \text{padding}, \min(\text{x}, \text{maxX} - \text{width} - \text{padding}))$$

2. **Vertical Alignment (Drag Direction Awareness)**:
 - **macOS Coordinates**: $Y$ increases upwards ($0$ is bottom of screen).
 - **Top-to-Bottom Drag**: When $(\text{releasePoint.y} - \text{mouseDownPoint.y}) < -10.0$, the selected text lies *above* the cursor release point. The popup is placed **BELOW** the cursor so selected text remains visible.
 - **Bottom-to-Top or Horizontal Drag**: The text lies below/beside the cursor. The popup is placed **ABOVE** the cursor.
 - **Screen Edge Clamping**: If placing above or below exceeds visible screen bounds, the algorithm automatically flips vertical placement.

---

## Content Mode: Native AI Result Card

Action and AI content render **inside** the single `PopupPanel` — there is no second
floating panel; status feedback renders separately as a floating toast via `ToastPanelController`
(see *Status* below). A `.content` mode on `PopupModeStore` (mirroring `.search`) transforms the panel:
the bar is hidden and `PopupView.barContent` renders `ResultCardView`, a native SwiftUI card
that replaced the former interactive canvas.

### Content Mode

- **Entry**: AI presets stream results into the card via `PopupView.onAIResult(text:isError:title:)` →
  `PopupWindowController.showResultCard`; any other text-returning action (e.g. a shell/JS extension)
  lands there through the delivery snapshot in `handleEffect`, which passes the performing action's
  customization-resolved icon alongside its title. Both set `modeStore.resultCard`
  (`ResultCardPayload { text, isError, title, icon, isStreaming, original }` — `original` is the
  selection the action ran on, carried so the card can diff it against the result),
  `modeStore.mode = .content`, and enter key mode.
  The card's chrome header (back chevron + the producing action's icon — sparkles when none,
  e.g. AI streaming — + title + optional diff toggle + close button `✕`) is rendered by `ResultCardView`
  (`Sources/OpenClip/UI/Popup/ResultCardView.swift`), with the back chevron wired to
  `PopupView.onExitContent` → `PopupWindowController.exitContent()`, and both the `✕` button and Esc wired to
  `PopupView.onDismissContent` → `hide()`.
- **Card surface**: the card renders a scrollable body plus a compact Copy/Paste footer (or a Dismiss button when
  `isError`; Paste also hidden while `modeStore.canPaste == false`), sized by `PopupMetrics`
  (`aiCardMinWidth 220` / `aiCardIdealWidth 320` /
  `aiCardMinHeight 200` / `aiCardMaxHeight 280`), measured against whichever body is showing
  (the diff is longer than the plain result) — unless a remembered size applies (see *Resizable*). The close action lives in the header (`✕`), keeping the footer
  clean and compact without requiring artificial width floors. Content mode is **key exactly like search**:
  the panel becomes key through the same `enterKeyMode()` primitive, and the card owns all keys
  via SwiftUI `.onKeyPress` — Esc closes the card outright (`hide()`, *not* a collapse back to the
  bar — the back chevron is what collapses); Return pastes and Shift+Return copies (Return falls
  back to copy when paste is unavailable); ⌘D toggles the diff when available. The controller monitor stays
  observation-only, with one exception: once the panel has lost key (the user clicked into the source
  document while a dragged card stayed up) it answers Esc itself, so the two can never double-fire.
- **Diff view**: `Core/Utils/TextDiff.swift` (pure domain) diffs `original` → `text` at character
  level — a Myers greedy diff over grapheme clusters, preceded by common prefix/suffix trimming,
  bounded by `maxComparableLength` (2 500 chars of changed middle) and `maxEditDistance` (300);
  exceeding either degrades to wholesale replacement.
  Diff availability is gated by `TextDiff.isMeaningfulEdit(from:to:)` — only genuine in-place revisions
  (proofreads, grammar fixes, tone tweaks with similarity $\ge 50\%$) show the diff toggle; wholesale
  rewrites (summaries, explanations, translations) and large texts automatically hide the diff button
  without hardcoding action IDs. When available, the card renders the segments as one attributed string:
  removed characters red + struck through, added characters green, both on a tinted background so a changed
  space is visible. The header toggle (`arrow.left.arrow.right`, also ⌘D) switches between diff and plain result.
  A streaming response is never diffed; the comparison waits for the final settled text.
- **Dragged to pin**: an un-dragged result card remains ephemeral and dismisses upon clicking outside, scrolling,
  or switching apps. If the user drags the card by its header, `PopupWindowController.hasUserMovedCard` sets
  `cardIsModal = true`, pinning the card against outside clicks in the source document.
  While pinned, `MacSelectionMonitor.isSuppressedForApp` suppresses selection detection specifically for
  the card's source app (`popup.sourceAppBundleID`), so selecting words in the source document to edit by hand
  cannot pop the action bar over the card being referenced. All other applications remain completely unsuppressed.
  Switching to another application or space dismisses the card and resets pinning.
- **Resizable, and the size is remembered**: the card's right edge, bottom edge and bottom-right
  grip are `PopupResizeHandles` (`Sources/OpenClip/UI/Popup/PopupResizeHandles.swift`) — SwiftUI
  `DragGesture`s, for the same reason as *Draggable* below: the borderless panel has no AppKit
  resize edges — that report `(PopupResizeEdge, ResultCardDragPhase)` to
  `PopupWindowController.handleResize`, shared with the search palette. The controller computes
  the new size from the **absolute** cursor position against the anchor taken at `began`
  (`PopupResizeGeometry.size`), clamps it to `aiCardMinWidth`/`aiCardMinHeight` and to the screen
  (`PopupResizeGeometry.clamp`, the panel's top-left corner is the fixed point), publishes it as
  `modeStore.resultCardSize` and sets the panel frame to card + shadow ring with the top-left
  fixed. The size is a **maximum**, not a fixed size: the card renders at what its text needs —
  as wide as its longest unwrapped line, as tall as that wrapped text — floored at
  `aiCardMinWidth` × `aiCardMinHeight` and capped by `maxSize` (the remembered size, or
  `aiCardIdealWidth` × `aiCardMaxHeight` by default), scrolling beyond it. That fit happens
  only when the card opens: once the user drags a handle (`modeStore.isSurfaceUserSized`, set at
  `began` and kept until the surface closes) the card renders the dragged size verbatim — any
  size they want, whatever the text does — with no settle on release. On
  `ended` the size is written to `SettingKey.resultCardWidth`/`resultCardHeight`
  (`Sources/OpenClip/Settings/SettingKey+ResultCard.swift`); every entry into content mode
  (`showResultCard`) reads it back, fitted to the current screen (`PopupResizeGeometry.fit`), and
  clears it again on `exitContent()`/`hide()`. Because a remembered card can be taller than the
  shared `popupMaxHeight`, content mode raises `PopupPanel.heightCap` to the screen height
  (restored on exit) and `fitPanelToContent()` nudges an automatically placed panel back on-screen
  after each fit. Resizing does not pin the card (`hasUserMovedCard` stays false) but, like a
  move, it drops the horizontal re-centering anchor. `ResultCardResizeTests` covers the geometry,
  the persistence round-trip and that the grip's gesture is actually delivered. Every
  text-returning action shares this surface: an extension's result, delivered inline
  (`handleEffect`) or through the loading re-show (`settleLoadingResult` → `show(for:)` →
  `showResultCard`), opens in the same card at the same remembered maximum —
  `ExtensionResultCardResizeTests` drives both paths with an extension-package action.
- **Draggable**: the header between the chevron and the diff/close actions carries a SwiftUI
  `DragGesture` that reports `ResultCardDragPhase` (`began`/`changed`/`ended`) to
  `PopupWindowController.handleCardDrag`, which moves the panel. AppKit dragging is **not**
  available here and three obvious routes are dead ends: the panel has no title bar,
  `isMovableByWindowBackground` never fires because the SwiftUI hosting view consumes the press,
  and an `NSViewRepresentable` handle never receives `mouseDown` either — `NSHostingView` answers
  `hitTest` with *itself* for the whole card and dispatches through SwiftUI's gesture system
  (`ResultCardModalTests.testHeaderDragGestureReachesTheCard` pins this). The move is computed from
  the **absolute** cursor position against an anchor taken at `began`, never from the gesture's
  translation: the window moves out from under the pointer, so a translation-based move fights
  itself. `prepareForUserDrag` sets `horizontalAnchor = .none`, so a later width change (the diff
  toggle resizes the card) keeps the user's placement instead of re-centering, and raises
  `isUserDragging`, which stops `updatePopupHover` from toggling `ignoresMouseEvents` mid-drag.
- **Follow-up field and the ask card**: above Copy/Paste the card carries an instruction field
  (`ResultCardView.followUpField`, shown whenever the host passes `onFollowUp` and the card is
  not an error). ⏎ with text runs `PopupWindowController.runFollowUp`, which calls
  `runAIPreset(prompt:title:inputText:)` with the card's *current text* as the input — a second
  pass over the answer — and re-streams the card in place, titled after the instruction
  (`AIPromptText.toolTitle`); `followUpSource` carries that input so the payload's `original` is
  the text the instruction ran on, not the selection, and the diff shows what the follow-up
  changed. ⏎ on an empty field keeps its old meaning (paste / copy). A settled card hands focus
  to the field (`focusCardField`, same next-run-loop nudge as the search field). The AI Tools
  list leads with **Ask…** (`AskAIAction`, `ai.ask`, `.ai` chrome, registered by `AIActionSync`
  ahead of the presets and excluded from their reconciliation via `InstructionPromptingAction`);
  every AI selection now goes through `runAISelection(actionID:)`, which runs a preset's prompt or
  opens the **ask card** — `ResultCardPayload.awaitsInstruction`: the selection as a dimmed body,
  no Copy/Paste yet, the field placeholder "What should AI do with this text?". The first
  instruction then runs on the selection like any follow-up. `ResultCardFollowUpTests` pins it.
- **Footer**: Paste (right) and Copy (left of it) both route through
  `PopupView.onCardEffect` → `PopupWindowController.performCardEffect` — an explicit request that
  bypasses the paste-vs-copy re-decision. Both dismiss the popup and perform (Paste pastes over
  the selection, Copy copies to the clipboard) — Copy behaves like Paste and closes too. An error
  card displays a "Dismiss" button. With the close action in the header, short result cards stay
  compact and neat without wrapping button labels.
- **Paste availability gating**: the trigger sites (hotkey handler, `MacSelectionMonitor`) start
  `PopupWindowController.preparePasteProbe(for:policy:)` in parallel with selection retrieval and hand the
  awaited result to `show(for:pasteAvailable:)`, which stores `modeStore.canPaste` before the first
  frame — no Paste/Cut flash. The result is the **unified** `PasteAvailability` answer (pure Core):
  the `denyPaste` per-app rule overrides the live AX probe, which fills in when no rule applies —
  one decision feeds gating *and* delivery, so rules are never hand-edited separately. `false` hides the card's Paste button
  and drops `PasteRequiringAction`s (built-in Paste/Cut) from the bar and search palette, via
  `PopupView.hiddenForPasteAvailability`. `nil`/unknown keeps everything visible — only a confirmed
  cannot-paste hides. Nothing is cached: with no rule, paste availability tracks the target app's
  *focus context* (editable field vs read-only view), so every show re-probes. The perform-time
  delivery re-decision reads the same unified value (`resolveDelivery`).
- **Status**: every `StatusFeedback` renders as a floating one-line toast anchored to the popup frame (flipping above when clamped, or centered on the main screen when no anchor exists) via
  `ToastPanelController` (`ToastPanel` + SwiftUI `ToastView`), independent of the popup — it shows
  whether the bar is up or already hidden. Info/error toasts auto-dismiss after
  `PopupMetrics.toastDurationNanoseconds` (1.2 s) unless `keepVisible: true`, which disables
  auto-dismiss; the paste→copy downgrade surfaces a "Copied"
  toast, or an action's declared per-click toast (`Action.delivery` `primaryToast`/`secondaryToast`)
  when one is declared (a script-emitted `.toast` suppresses these — one toast per run). The inline banner and its queue (`modeStore.statusBanner`, `pendingStatus`,
  `flushPendingStatus`) are gone. `showsLoading` actions (manifest `"loading"`) early-close the
  popup with a spinner toast, swapping to a description, the resolved companion toast, or fading on
  a description-free result (a keep-visible toast stays up rather than auto-dismissing).
- **Secondary-click threading**: the click intent captured at mouse-down (`pendingClickIntent`) is
  threaded into the perform context as `ActionContext.isSecondaryClick` (right-click always; ⇧-click
  via `PopupView`/`PopupSearchView`'s `onClickIntent` closure) and into the delivery snapshot
  (`DeliveryContext.clickIntent`, alongside the action's declared `Action.delivery`). Actions can
  branch on it — `DefineAction` returns `.copyDefinition(word)` on a secondary click (with a
  declared `secondaryToast` "Copied definition") so the effect door copies the dictionary definition
  headlessly instead of opening Dictionary.app.

---

## Action-Search Palette & Panel Growth

The ⌥⌘C hotkey toggles the popup through a **mode state machine**: actions bar → action-search
palette → dismiss (`HotkeyManager` calls `PopupWindowController.toggleMode()` when the popup is
already visible; the bar's command-glyph button enters search via `onEnterSearch`).

### Search Mode

- **Mode state**: [`PopupModeStore`](../../Sources/OpenClip/UI/Popup/PopupModeStore.swift) holds
  `mode` (`.actions`/`.search`/`.content`), `searchResultsAbove` (set from `cardAbove` in
  `show(for:)`), plus the content payload `resultCard` (which carries the `original` selection for
  the card's diff). Statuses live in the floating toast, not the
  store. `PopupView` branches on `modeStore.mode` in `unifiedHStack` and renders
  `PopupSearchView` — the field + result list rendered as **one surface** with the bar, results
  above or below the field by `searchResultsAbove`.
- **Catalog, matching & prewarming**: the palette lists what the user can actually run — anything switched off
  in settings is absent, matching the bar: per-action (`disabledActionIDs`), whole-package
  (`disabledPackages`), a disabled group (its members go with it, since the palette lists members
  rather than the row), and an AI preset whose toggle in AI → Actions is off (or with AI disabled
  wholesale), which `AIAction.isEnabled` reports. Context gating drops the rest
  (`isEnabled(for:)`, clipboard-fallback vs `requiresLiveSelection`). Via
  `ActionCoordinator.searchCatalog` → `ActionRegistry.searchCatalog`; `ActionSearch`
  ranks by case-insensitive substring (prefix > contains > keyword). Up to `PopupMetrics.searchMaxRows`
  rows render (`searchMaxRows = 5`, `searchResultRowHeight = 32`, height capped by
  `PopupMetrics.popupMaxHeight`).
  To ensure instant palette presentation on hotkey (⌥⌘C), `PopupSearchView.prewarmIndex(catalog:)`
  builds and caches the search index during passive selection monitoring. The cache tracks both
  `catalogIDs` and `usageRecency`; if both match upon opening an unscoped palette, the prewarmed
  index is reused directly without re-indexing.
- **Row icons are strictly `[icon | text]`**: a `.text` icon falls back to
  `ConfigurableAction.preferenceIconName`; Iconify-format symbols (`prefix:name`) render via
  `AnyIconView`, matching the bar (`PopupSearchView.swift:214,230`).
- **Escape** clears the query first, then exits to the actions bar. In a **scoped** sub-action
  palette, Escape instead drops the scope (`PopupSearchView.exitSearch()` → `onExitScope`) and
  closes back to the bar.
- **Row shortcuts**: ⌘1…⌘9 run the first nine rows outright (`PopupSearchView.runRow(at:)`), with
  the label drawn on the row (`shortcutHint(forRow:)`); rows past the ninth have none, and a digit
  with no matching row falls through to the field rather than being swallowed. Because OpenClip's
  popup is a non-activating panel (macOS routes command-modified keys to the active app), these
  shortcuts are registered as global Carbon hot keys via `PaletteRowShortcuts.swift`, activated
  strictly while the palette is visible and parked the moment it closes — alongside arrows, Return,
  hover, and click.
- **Resizable, and the size is remembered**: the palette carries the same `PopupResizeHandles`
  as the result card (right edge, bottom edge, corner grip) and goes through the same
  `PopupWindowController.handleResize` / `PopupResizeGeometry` path, with its own floor
  (`searchPaletteMinWidth` 240 / `searchPaletteMinHeight` 128) and its own keys
  (`SettingKey.searchPaletteWidth`/`searchPaletteHeight`,
  `Sources/OpenClip/Settings/SettingKey+SearchPalette.swift`). The live size is
  `modeStore.searchPaletteSize`, rendered by `PopupSearchView` as `maxSize` — a **maximum**: the
  palette is as tall as its current results need (`PopupSearchView.height(forRows:)`, floored at
  `searchPaletteMinHeight`) and as wide as the default column or its widest row
  (`naturalRowWidth(for:)`, measured once per result set), each capped by the remembered size, or
  by the default `searchPanelContentWidth` × `defaultHeight` column when nothing is remembered.
  That fit happens only on entry: once the user drags a handle (`modeStore.isSurfaceUserSized`)
  the palette keeps the dragged size verbatim until it closes. Because the
  height now follows the result count, the entry growth's bottom-edge pin is **one-shot**
  (`PopupPanel.releasesBottomPinAfterGrowth`, armed by `enterSearch()` on a fresh entry only):
  later changes keep the field at the palette top fixed, a directly opened palette is never
  pinned, and `exitSearch()` puts the bottom edge back on the bar's original spot
  (`preSearchFrame.minY`) before the collapse pins it. The size is restored on both entry paths —
  `enterSearch()` (fresh entry only, not a scope hop; the palette is then placed with its
  remembered width) and `show(for:initialMode: .search)` (before the view is built, so the first
  frame is already right) — both of which also raise `PopupPanel.heightCap` to the screen height
  and schedule `keepPanelOnScreen()` after the hosting view's growth; `exitSearch()` clears the
  live size and restores the cap *after* its own frame restore, so a tall palette is not clamped
  mid-collapse. `SearchPaletteResizeTests` pins all of this.
- **Placement is the same for both entry points.** A palette opened directly by the hotkey
  (`show(for:initialMode:.search)`) goes through `PopupPositioner.calculateFrame` /
  `positionPanel` exactly like the bar the mouse opens: anchored on the selection, honoring the
  `popupAlignment` and `popupVerticalPosition` preferences, and clamped to the screen containing
  the cursor. It used to be centred on the main screen, which ignored both settings and put the
  palette nowhere near the text. Entering search *from the bar* still re-anchors to the bar
  instead (`enterSearch(buttonLocalFrame:)` + `preSearchFrame`), so the field opens over the row
  that was clicked.

### Scoped Sub-Action Palette

Opening a group/AI bar row and reaching the palette from hotkey are the same surface, differing only
in `modeStore.scope`:

- **Entering scoped**: a bar click on a group row (`.openSubActions`) or the AI Tools launcher
  (`chrome.launchesAI`) calls `PopupWindowController.enterScopedSearch(for:)`
  (`PopupWindowController.swift:158`), which resolves the parent's children via the Core
  `SubActionResolver` over `searchCatalog` and calls `enterSearch(with: SearchScope(parent:children:))`.
  `modeStore.scope` (added Task 5) carries the parent + pre-resolved children.
- **Membership is protocol-driven**: `GroupAction` and `AIToolsAction` conform to `SubActionProviding`
  (Core, `SubAction.swift`); resolution is id-prefix/`.ai` driven, never `switch action.id`.
- **Scoped view behavior**: `PopupSearchView` matches/search-catalogs only `scope.children`
  (`PopupSearchView.swift:49`), swaps the field's leading icon to the parent's, and the placeholder
  reads **"Search within <parent.title>"**. Esc (`onExitScope`) drops the scope; the leading icon and
  placeholder come from `actionIcon(parent)/parent.displayTitle`.

### Key-Mode Exceptions

Search and content (AI-card) modes both make the panel key — the only two exceptions to the
never-key rule. Both route through the same primitives: `enterKeyMode()`
(`PopupWindowController.swift:196`) captures `previousFrontmostApp` when none exists yet
(`show(for:)` captures it once at session start; mid-session re-entry never re-captures), sets
`panel.allowsKey = true`, and calls `makeKeyAndOrderFront`; `exitKeyMode()` (`:206`) restores the
invariant and re-activates `previousFrontmostApp`. Search then forces focus on the **next run-loop
turn** via `focusSearchField()`/`findTextInput` (`:245`) because a `@FocusState`-in-onAppear request
is silently dropped before the panel finishes becoming key; `exitSearch()` (`:264`) restores the
invariant. `showResultCard` enters content mode the same way; the result card owns all keys through
SwiftUI `.onKeyPress`. `hide()` is the only thing that clears `previousFrontmostApp` —
`exitKeyMode()` deliberately keeps it, so the same source app is re-activated on the next exit and
re-used on the next enter.

### Panel-Growth Anchoring (content-driven resize)

The `NSHostingView` auto-resizes the panel **top-anchored** when its SwiftUI content grows, with
**no callback** to the controller (`onPreferenceChange`/`onContentSizeChange` never fires;
`sizingOptions` has no effect). Two layers handle this:

1. **`resizePanel(to:)`** (`PopupWindowController.swift:414`) anchors the field's edge when the
   controller drives a size change: results-below (field at palette top) keeps `maxY` fixed and
   grows down; results-above (field at palette bottom) keeps `minY` fixed and grows up.
2. **`PopupPanel.setFrame`** (`PopupPanel.swift:42`) intercepts *every* resize the hosting view
   performs on its own and, when `pinBottomEdgeOnResize` is set, pins the bottom edge before the
   frame displays — so the auto-resize for results-above growth doesn't shove the popup off the
   cursor. The pin is set when entering search or content mode (when `searchResultsAbove`). For
   search it is armed together with `releasesBottomPinAfterGrowth`, so it spends itself on the
   entry growth: the palette's height then follows the result count, and those later changes keep
   the top edge (the field) fixed. `exitSearch()` re-arms the plain pin **for the search→bar
   collapse** after putting the bottom edge back on the bar's original spot, so the bar returns
   there (Esc no longer jumps the popup); `show(for:)` and `hide()` clear both before intentional
   placement.
3. **Horizontal re-centering** lives with the y-pin in `PopupPanel.setFrame`, not the controller:
   while `recenterXOnResize` is set (armed by `show(for:)` right after placement, cleared before a
   fresh placement), a width change keeps the panel centered on its current `midX` instead of the
   hosting view's top-left-anchored default — so swapping to the 280pt search palette or a shorter
   pagination page never drifts the bar off the cursor. `PopupPositioner.centeredX` clamps the
   initial placement; resize only preserves the existing center.

Behavioral contract is pinned by `Tests/OpenClipTests/PopupPanelTests.swift` (top/bottom edge fixed
on enter, bar returns to position on exit, panel key + field first-responder on re-entry).
