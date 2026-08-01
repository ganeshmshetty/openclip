# Global Keyboard Shortcuts

OpenClip offers hotkey activation and keyboard-friendly navigation for fast, mouse-free text workflows.

---

## Global Trigger Hotkey

You can configure a system-wide global shortcut to manually trigger the OpenClip HUD popup over currently selected text. This is particularly useful if:
- Automatic text selection detection fails in a non-standard app.
- You have disabled automatic selection detection for an app, but still want to trigger OpenClip on demand.

### Setting the Global Hotkey

1. Open **Preferences** (`Cmd + ,`).
2. Go to the **General** tab.
3. Locate **Trigger Popup Shortcut**.
4. Click the recorder field and press your desired key combination (e.g. `Option + Space` or `Cmd + Shift + C`).

---

## Popup HUD Keyboard Navigation

When the OpenClip popup HUD appears on screen, you can navigate and execute actions directly using your keyboard:

| Shortcut / Key | Action |
|----------------|--------|
| `Left Arrow` / `Right Arrow` | Move focus between action buttons in the popup. |
| `Space` / `Return` | Trigger the currently focused action. |
| `1` - `9` | Trigger action 1 through 9 directly by number key. |
| `Escape` (`Esc`) | Instantly dismiss the popup HUD. |

---

## Modifier Flags Support

OpenClip actions can react to keyboard modifier keys (`Shift`, `Option`, `Command`, `Control`) held down when clicking an action button or pressing `Return`:

- **Standard Click:** Executes default action (e.g. Copy text to clipboard).
- **Shift + Click:** Executes secondary behavior (e.g. Paste formatted text).
- **Option + Click:** Opens action configuration sheet or web preview.

This allows single action buttons in OpenClip to provide multiple execution modes!
