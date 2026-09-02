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
- **Dismissal Threshold**: Automatically dismisses the popup if the cursor moves beyond `PopupMetrics.popupDismissalDistance` (suspended in search mode and while a content/AI-card is open).
- **Keyboard Dismissal**: Requires Accessibility permission (the global monitor). In actions mode any key — including `Escape` — dismisses the popup; the global monitor is observation-only, so the keystroke still lands in the source app's document and the panel never needs to become key. In search mode the panel *is* key, so keys go to the search field (`Escape` clears a scoped query, then exits). In content mode the panel is *also* key: the AI result card owns all keys via SwiftUI `.onKeyPress`, `Escape` collapses the card back to the bar (`exitContent()`), and the controller monitor stays observation-only so it never double-fires Esc.

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
  (`ResultCardPayload { text, isError, title, icon, isStreaming }`), `modeStore.mode = .content`,
  and enter key mode.
  The card's chrome header (back chevron + the producing action's icon — sparkles when none,
  e.g. AI streaming — + title) is rendered by `ResultCardView`
  (`Sources/OpenClip/UI/Popup/ResultCardView.swift`), with the back chevron wired to
  `PopupView.onExitContent` → `PopupWindowController.exitContent()`.
- **Card surface**: the card renders a scrollable body plus a Copy/Paste footer (hidden when
  `isError`; Paste also hidden while `modeStore.canPaste == false`), sized by `PopupMetrics`
  (`aiCardMinWidth 220` / `aiCardIdealWidth 300` /
  `aiCardMaxWidth 360` / `aiCardBodyHeight 120`). Content mode is **key exactly like search**:
  the panel becomes key through the same `enterKeyMode()` primitive, and the card owns all keys
  via SwiftUI `.onKeyPress` — Esc collapses the card back to the bar (`exitContent()`); Return
  pastes and Shift+Return copies (Return falls back to copy when paste is unavailable); the
  controller monitor observes content Esc only so non-key transitions still collapse.
- **Copy/Paste footer**: Paste (right) and Copy (left of it) both route through
  `PopupView.onCardEffect` → `PopupWindowController.performCardEffect` — an explicit request that
  bypasses the paste-vs-copy re-decision. Both dismiss the popup and perform (Paste pastes over
  the selection, Copy copies to the clipboard) — Copy behaves like Paste and closes too.
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
  `show(for:)`), plus the content payload `resultCard`. Statuses live in the floating toast, not the
  store. `PopupView` branches on `modeStore.mode` in `unifiedHStack` and renders
  `PopupSearchView` — the field + result list rendered as **one surface** with the bar, results
  above or below the field by `searchResultsAbove`.
- **Catalog & matching**: the palette searches the **full** catalog (enabled + disabled, no context
  filtering) via `ActionCoordinator.searchCatalog` → `ActionRegistry.searchCatalog`; `ActionSearch`
  ranks by case-insensitive substring (prefix > contains > keyword). Up to `PopupMetrics.searchMaxRows`
  rows render (`searchMaxRows = 5`, `searchResultRowHeight = 32`, height capped by
  `PopupMetrics.popupMaxHeight`).
- **Row icons are strictly `[icon | text]`**: a `.text` icon falls back to
  `ConfigurableAction.preferenceIconName`; Iconify-format symbols (`prefix:name`) render via
  `AnyIconView`, matching the bar (`PopupSearchView.swift:214,230`).
- **Escape** clears the query first, then exits to the actions bar. In a **scoped** sub-action
  palette, Escape instead drops the scope (`PopupSearchView.exitSearch()` → `onExitScope`) and
  closes back to the bar.

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
   cursor. The pin is set when entering search or content mode (when `searchResultsAbove`) and **stays
   active through the search→bar collapse**, so the bar returns to the field's spot (Esc no longer
   jumps the popup); `show(for:)` and `hide()` clear it before intentional placement.
3. **Horizontal re-centering** lives with the y-pin in `PopupPanel.setFrame`, not the controller:
   while `recenterXOnResize` is set (armed by `show(for:)` right after placement, cleared before a
   fresh placement), a width change keeps the panel centered on its current `midX` instead of the
   hosting view's top-left-anchored default — so swapping to the 280pt search palette or a shorter
   pagination page never drifts the bar off the cursor. `PopupPositioner.centeredX` clamps the
   initial placement; resize only preserves the existing center.

Behavioral contract is pinned by `Tests/OpenClipTests/PopupPanelTests.swift` (top/bottom edge fixed
on enter, bar returns to position on exit, panel key + field first-responder on re-entry).
