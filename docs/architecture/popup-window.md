# Floating Popup Panel Architecture

The floating popup panel subsystem presents contextual actions near the user's cursor or text selection. It consists of `PopupPanel` (an `NSPanel` subclass), static frame math in `PopupPositioner`, SwiftUI rendering in `PopupView`, and lifecycle coordination via `PopupWindowController`.

---

## Window Components

```
+-----------------------------------------------------------------------------+
| PopupWindowController |
| ├── PopupPanel (NSPanel, non-activating, borderless, floating level) |
| │ └── NSHostingView(PopupView) |
| │ └── Action Buttons / Sub-menus |
| ├── AI PopupPanel (Secondary panel for AI responses) |
| │ └── NSHostingView(AIResultOverlayView) |
| └── Event Monitors (Global / Local NSEvent tracking) |
+-----------------------------------------------------------------------------+
```

### 1. [`PopupPanel`](../../Sources/OpenClip/UI/Popup/PopupPanel.swift)
- **Base Class**: `NSPanel`
- **Window Style**: `.nonactivatingPanel`, `.borderless`
- **Window Level**: `.floating` (sits above normal application windows). The panel is deliberately **never** the key window (`canBecomeKey` stays the default `false`); making it key would steal keyboard focus from the active app and swallow keystrokes.
- **Properties**: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` (SwiftUI draws its own shadow; a panel shadow causes double artifacts).

### 2. [`PopupWindowController`](../../Sources/OpenClip/UI/Popup/PopupWindowController.swift)
- **Responsibility**: Controls window creation, display lifecycle, event monitoring, hover tracking, and AI overlay panel positioning.
- **Event Handling**: Sets up local and global `NSEvent` monitors (`.leftMouseDown`, `.mouseMoved`, `.scrollWheel`, `.keyDown`). The local monitor sees mouse events over the panel; the global monitor sees events system-wide.
- **Dismissal Threshold**: Automatically dismisses the popup if the cursor moves beyond `Constants.popupDismissalDistance` (unless a blocking bubble is active).
- **Keyboard Dismissal**: Requires Accessibility permission (the global monitor). Any key — including `Escape` — dismisses the popup. The global monitor is observation-only, so the keystroke still lands in the source app's document; the panel never needs to become the key window.

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

## AI Result Overlay Sub-System

When an AI action (such as text summary or rewrite) is performed:

1. `PopupWindowController` receives an AI result callback.
2. `showAIPanel(text:isError:cardAbove:)` instantiates a secondary `PopupPanel` for `AIResultOverlayView`.
3. The AI overlay card is positioned directly adjacent to the main action bar (above or below depending on available vertical space).
4. The main action bar remains anchored while the AI card displays streaming or final response text.
5. User actions on the AI overlay (such as "Replace Selection" or "Copy Text") route execution through `ActionResultHandler`.
