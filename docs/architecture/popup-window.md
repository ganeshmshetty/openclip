# Floating Popup Panel Architecture

The floating popup panel subsystem presents contextual actions near the user's cursor or text selection. It consists of `PopupPanel` (an `NSPanel` subclass), static frame math in `PopupPositioner`, SwiftUI rendering in `PopupView`, and lifecycle coordination via `PopupWindowController`.

---

## Window Components

```
+-----------------------------------------------------------------------------+
| PopupWindowController |
| ├── PopupPanel (NSPanel, non-activating, borderless, floating level) |
| │ └── NSHostingView(PopupView) |
| │ ├── Action Buttons / Sub-menus |
| │ ├── PopupContentView (inline content canvas in .content mode) |
| │ ├── PopupPreviewStrip (inline hover preview) |
| │ └── Status banner / corner badge (inline status) |
| └── Event Monitors (Global / Local NSEvent tracking) |
+-----------------------------------------------------------------------------+
```

### 1. [`PopupPanel`](../../Sources/OpenClip/UI/Popup/PopupPanel.swift)
- **Base Class**: `NSPanel`
- **Window Style**: `.nonactivatingPanel`, `.borderless`
- **Window Level**: `.floating` (sits above normal application windows). The panel is deliberately **never** the key window by default; making it key would steal keyboard focus from the active app and swallow keystrokes. The **only** exception is action-search mode: `PopupPanel.allowsKey` gates `canBecomeKey`/`canBecomeMain`, enabled solely by `PopupWindowController.enterSearch()`. Content mode is **not** an exception — Esc is handled by the event monitors (observation-only).
- **Properties**: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` (SwiftUI draws its own shadow; a panel shadow causes double artifacts). `pinBottomEdgeOnResize` (search/content mode only) re-anchors content-driven growth — see *Action-Search Palette & Panel Growth* below.
- **Shadow inset**: `PopupView` keeps ≥16pt of SwiftUI padding around the bar (12pt for info cards in `PopupContentView`) so the SwiftUI shadow renders *inside* the panel rather than being clipped at its edge. If a shadow looks cut off, increase the padding — never re-enable the panel shadow.

### 2. [`PopupWindowController`](../../Sources/OpenClip/UI/Popup/PopupWindowController.swift)
- **Responsibility**: Controls window creation, display lifecycle, event monitoring, hover tracking, and the popup mode state machine (actions bar ↔ search palette ↔ content canvas).
- **Event Handling**: Sets up local and global `NSEvent` monitors (`.leftMouseDown`, `.mouseMoved`, `.scrollWheel`, `.keyDown`). The local monitor sees mouse events over the panel; the global monitor sees events system-wide.
- **Dismissal Threshold**: Automatically dismisses the popup if the cursor moves beyond `Constants.popupDismissalDistance` (suspended in search mode and while a blocking content canvas — `.result`/`.menu` — is open).
- **Keyboard Dismissal**: Requires Accessibility permission (the global monitor). In actions mode any key — including `Escape` — dismisses the popup; the global monitor is observation-only, so the keystroke still lands in the source app's document and the panel never needs to become key. In search mode the panel *is* key, so keys go to the search field (`Escape` clears a scoped query, then exits). In content mode the panel stays non-key: `Escape` collapses the canvas back to the bar (`exitContent()`), any other key dismisses.

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

## Content Canvas (inline results, no floating panel)

All action/AI/hover/status content renders **inside** the single `PopupPanel` — there is no second
floating panel. A `.content` mode on `PopupModeStore` (mirroring `.search`) transforms the panel:
the bar is hidden and `PopupView.barContent` renders `PopupContentView` with the canvas.

### Content Mode

- **Entry**: `PopupWindowController.enterContent(_:)` sets `modeStore.content` then `modeStore.mode = .content`.
  Every former bubble source routes into the store: `handleActionResult(.showContent(...))`, the AI
  result (`showAIContent`), and the long-press result card (`beginLongPressIfNeeded` →
  `ResultContentProviding.makeContent`).
- **Canvas renderer**: `PopupContentView` (`PopupContentView.swift`) renders a `PopupContent` with
  one of three emphasis styles — `.info` (small dim card), `.result` (standard card with a header
  row and delivery buttons), `.menu` (vertical option rows). The header shows the content title and
  a **back chevron** when `onBack` is provided, wired to `PopupView.onExitContent` →
  `PopupWindowController.exitContent()`.
- **Non-key Esc**: content mode is **not** a key-window exception. `exitContent()` collapses the
  canvas back to the bar without hiding the popup; the global event monitor observes Esc in content
  mode and calls it. `handleActionResult` is internal so tests drive the canvas directly.
- **Canvas outcomes**: footer/menu options resolve through `PopupView.onContentOutcome`; the
  controller preserves the old bubble paste-vs-copy UX — a `.paste` outcome hides the popup after
  delivering, anything else collapses to the bar then handles the effect.
- **Status**: with no canvas open, a `StatusFeedback` shows as an inline auto-dismissing banner
  (`modeStore.statusBanner`, cleared after ~1.5s); with a canvas open it becomes a top-trailing
  corner badge on the card via `StatusBadgeModel.shared`.

### Hover Preview Strip

Hovering an action whose `gesturePolicy.hoverPreview` is set (`PreviewProviding`) shows a compact
inline strip (`PopupPreviewStrip`, `PopupPreviewStrip.swift`) stacked with the bar — above the bar
when `searchResultsAbove`, below otherwise. The bar stays visible; the panel grows via the existing
content-driven resize. The `.info` hover card from the old floating bubble is gone.

---

## Action-Search Palette & Panel Growth

The ⌥⌘C hotkey toggles the popup through a **mode state machine**: actions bar → action-search
palette → dismiss (`HotkeyManager` calls `PopupWindowController.toggleMode()` when the popup is
already visible; the bar's command-glyph button enters search via `onEnterSearch`).

### Search Mode

- **Mode state**: [`PopupModeStore`](../../Sources/OpenClip/UI/Popup/PopupModeStore.swift) holds
  `mode` (`.actions`/`.search`/`.content`), `searchResultsAbove` (set from `cardAbove` in
  `show(for:)`), plus the canvas payloads `content`, `preview`, and `statusBanner`.
  `PopupView` branches on `modeStore.mode` in `unifiedHStack` and renders
  `PopupSearchView` — the field + result list rendered as **one surface** with the bar, results
  above or below the field by `searchResultsAbove`.
- **Catalog & matching**: the palette searches the **full** catalog (enabled + disabled, no context
  filtering) via `ActionCoordinator.searchCatalog` → `ActionRegistry.searchCatalog`; `ActionSearch`
  ranks by case-insensitive substring (prefix > contains > keyword). Up to `Constants.searchMaxRows`
  rows render (`searchMaxRows = 3`, `searchResultRowHeight = 32`, `searchMaxHeight = 176` cap).
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

### Scoped Key Exception

Search mode makes the panel key — the sole exception to the never-key rule. `enterSearch()`
captures `previousFrontmostApp`, sets `panel.allowsKey = true`, and calls `makeKeyAndOrderFront`
(`PopupWindowController.swift:143`). Focus is forced on the **next run-loop turn** via
`focusSearchField()`/`findTextInput` (`:161`) because a `@FocusState`-in-onAppear request is
silently dropped before the panel finishes becoming key. `exitSearch()` restores the invariant and
re-activates `previousFrontmostApp`; `hide()` does the same.

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
   cursor. The pin is set by `enterSearch`/`enterContent` (when `searchResultsAbove`) and **stays
   active through the search→bar collapse**, so the bar returns to the field's spot (Esc no longer
   jumps the popup); `show(for:)` and `hide()` clear it before intentional placement.

Behavioral contract is pinned by `Tests/OpenClipTests/PopupPanelTests.swift` (top/bottom edge fixed
on enter, bar returns to position on exit, panel key + field first-responder on re-entry).
