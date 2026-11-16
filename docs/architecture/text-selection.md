# Text selection subsystem architecture

The text selection subsystem detects user text selection events across all macOS applications and extracts selected text non-destructively, then hands it to the popup.

## Selection detection architecture

The subsystem consists of three primary components:

```mermaid
flowchart TD
  M["MacSelectionMonitor<br/>global mouse and AX events"] --> R["RuleEngine<br/>per-app policy"]
  M -->|builds| S[SelectionContext]
  M --> C["SelectionRetrievalCoordinator<br/>gate and mode routing"]
  R --> S
  S --> O["onSelection callback<br/>PopupWindowController"]
  C --> O
```

1. **[`MacSelectionMonitor`](../../Sources/OpenClip/Platform/MacSelectionMonitor.swift)**: Listens for mouse release events (`leftMouseUp`) and keyboard selection gestures (⌘A select-all, ⇧+arrow) and dispatches retrieval.
2. **`SelectionRetrievalCoordinator`** (from `OpenSelection` package via [`OpenSelectionBridge`](../../Sources/OpenClip/Platform/Selection/OpenSelectionBridge.swift)): Applies the gate, resolves the app's retrieval mode from [`AppPolicyContext`](../../Sources/Core/Rules/AppRule.swift), and routes to the matching strategy.
3. **Context assembly**: `MacSelectionMonitor` resolves app rules via [`RuleEngine`](../../Sources/Core/Rules/RuleEngine.swift), builds a [`SelectionContext`](../../Sources/Core/Selection/SelectionContext.swift), and notifies subscriber callbacks (such as `PopupWindowController`).

The monitor snapshots the window under a mouse press and rejects the release if that window
moved, resized or disappeared. This avoids retrieving an old selection from the editor that
remains focused while its title bar is dragged. New presses and switches away from the source
process cancel pending automatic reads and clear the shortcut cache. Queued notifications for
apps no longer frontmost, the source app's own activation, and OpenClip's popup activation are
ignored. The monitor rechecks the source PID before caching or presenting results after async
work. At the copy boundary, OpenSelection's [`AutomaticCopyCapture`](https://github.com/ganeshmshetty/OpenSelection#passive-monitoring)
requires an enabled Command-C menu shortcut, then rechecks cancellation, the frontmost process
and the overlay guard before invoking the copy trigger. The bounded menu probe runs off the
main actor. Native AX retrieval and the explicit hotkey use their existing behavior. See
[current limitations](known-debt.md#selection-retrieval).

The shared capture and window-geometry implementations live in OpenSelection. OpenClip retains
only its app-specific monitor lifecycle (including hold-to-trigger and cached selections).

## Retrieval: resolver, gate, and strategies

Every retrieval request (mouse-up drag, ⌘A/⇧+arrow gesture, or the ⌥⌘C hotkey) runs through `SelectionRetrievalCoordinator.retrieve(for:policy:cursor:)`:

1. **Fresh AX snapshot**: `AXElementInspector.inspect()` resolves the focused application, then the focused UI element *from that application*, never from the system-wide element (the classic source of stale reads). It collects the role, parent/container roles, selection attributes, and selection bounds. The blocking snapshot runs on the dedicated `com.openclip.ax-inspect` queue, raced against `Constants.axReadTimeout` (0.5 s) via a once-resume gate; a hung or unresponsive target yields `nil` instead of stalling the popup.
2. **Gate**: [`SelectionGatePolicy`](../../Sources/Core/Rules/SelectionGatePolicy.swift) decides whether to attempt retrieval at all:
   - `skipRoles`: AX roles that can never hold a text selection (buttons, menus, scrollbars, etc.) are rejected up front.
   - `allowedCursors`: the cursor class (from `CursorClassifier` in `OpenSelection`) must suggest a text context. `.unknown` is never a reason to block.
3. **Strategy chain**: a single canonical fallback order selects the first working strategy. The app's [`SelectionRetrievalMode`](../../Sources/Core/Rules/SelectionRetrievalMode.swift) picks the *entry point* into that chain; retrieval then runs that strategy and every strategy below it. An app with no rule starts at `ax-text-control` (the top), which is the "auto" behavior.

The canonical chain:

```
ax-text-control → ax-web-area → menu-copy → keyboard-copy
```

```mermaid
flowchart TD
  Start[Retrieval Request] --> Inspect[Fresh AX snapshot<br/>race axReadTimeout 0.5 s]
  Inspect -- nil timeout --> Nil[no selection]
  Inspect -- snapshot --> Gate{SelectionGatePolicy}
  Gate -- role in skipRoles --> Nil
  Gate -- cursor not allowed --> Nil
  Gate -- select-all on non-text --> Nil
  Gate -- pass --> Chain[Run chain from preferred entry point<br/>first non-blank result wins]
  Chain --> AXText[AXTextControlStrategy]
  Chain --> AXWeb[AXWebAreaStrategy<br/>settle-retry x6, fresh inspect each]
  Chain --> MenuCopy[Menu copy]
  Chain --> KBCopy[Keyboard copy]
  AXText --> Out[TextResult]
  AXWeb --> Out
  MenuCopy --> Out
  KBCopy --> Out
```

Chain suffix per preferred mode:

| Preferred mode | Strategies run (in order) |
| :--- | :--- |
| `ax-text-control` (default / no rule) | AX text → (embedded web-area detected? AX web area → keyboard copy; otherwise AX text → keyboard copy) |
| `ax-web-area` (browsers) | AX web area → keyboard copy |
| `browser-script` (legacy alias) | AX web area → keyboard copy |
| `menu-copy` | menu copy |
| `keyboard-copy` | keyboard copy |

Web selections run directly through native Accessibility (`AXWebArea`), reading `kAXSelectedTextMarkerRange` in <1 ms without spawning subprocesses or requiring Apple Events permissions. If Accessibility yields no text (e.g. Google Docs canvas or custom editors), the coordinator falls back to `keyboard-copy`.

### Retrieval modes

| Mode | kebab-case key | Strategy |
| :--- | :--- | :--- |
| AX native text control | `ax-text-control` | `AXTextControlStrategy` reads `kAXSelectedTextAttribute` (falling back to `value` + `selectedTextRange` substring) and the selection bounds. Zero pasteboard side-effects. Default. |
| AX web area | `ax-web-area` | `AXWebAreaStrategy` reads `kAXSelectedTextMarkerRange` → `AXStringForTextMarkerRange` (fallback `selectedText`). Includes a settle-retry loop: the snapshot is re-inspected fresh on every retry (up to `webAreaSettleMaxRetries` = 6, `webAreaSettleInterval` = 50 ms apart) so text appearing after focus is observed instead of a frozen target. `AXElementInspector` walks up to 25 ancestor levels and searches the window on focus mismatch. |
| Browser script (legacy) | `browser-script` | Formerly used AppleScript `execute javascript`; now maps directly to `ax-web-area` with `keyboard-copy` fallback to eliminate subprocess latency and permission friction. |
| Menu copy | `menu-copy` | `PasteboardCopyEngine` archives the pasteboard, AXPresses the app's **Edit ▸ Copy** menu item (matched by action identifier `copy:`, ⌘C key equivalent, or localized title via `AXMenuNavigator`), polls for an advanced `changeCount` with non-empty text, then restores. The press shares `inspectGate` and uses `axReadTimeout`, same as inspect. Used for terminals. |
| Keyboard copy | `keyboard-copy` | The same engine with a synthesized ⌘C key event (`SessionEventTapPoster`) as the trigger. Used for custom code editors and Electron apps whose AX selection reads are unreliable. |

### The copy engine and transient markers

Both copy modes run through [`PasteboardCopyEngine`](../../Sources/OpenClip/Platform/PasteboardCopyEngine.swift): archive every type of every pasteboard item → run the trigger → poll every 2 ms up to a per-app timeout (`pasteboardCopyTimeout` 0.25 s, or `safariPasteboardCopyTimeout` 0.6 s for browsers) for an advanced `changeCount` yielding non-empty text (a `changeCount` advance with empty content keeps polling, covering the transient clipboard race; recopying identical text succeeds as long as `changeCount` advances) → read the new string → restore the archived items **synchronously before returning**, tagged with the **nspasteboard markers** `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType` (empty data). The markers tell clipboard managers to skip the restore as a user-visible copy. The clipboard is therefore clean by the time retrieval returns; there is no lingering visibility window.

### Per-app routing (default catalog)

`DefaultAppRules.catalog` assigns modes to app groups; `RuleEngine.resolvePolicies` matches the frontmost app's identity (bundle ID, or a `process:`/`path:` identifier for bundle-less apps) against default + user rules (with `.*` prefix / `*` wildcards). User rules in `~/.openclip/rules.json` override per key. See `docs/user-guide/app-rules.md` for the JSON keys.

| Group | Target Application Category | Mode |
| :--- | :--- | :--- |
| `safariGroup` | Safari & WebKit-based browsers | `ax-web-area` |
| `chromiumGroup` | Chromium-based browsers | `ax-web-area` |
| `firefoxGroup` | Firefox & Gecko-based browsers | `ax-web-area` |
| `arcGroup` | Arc browsers | `ax-web-area` |
| `keyboardCopyApps` | Code editors, IDEs, markdown & note apps | `keyboard-copy` |
| `menuCopyApps` | Terminal emulators | `menu-copy` |
| `denyPasteApps` | Applications requiring paste suppression | `denyPaste: true` |
| default | All other standard applications | `ax-text-control` |

## Shortcut presentation

The global toggle shortcut ([`HotkeyManager`](../../Sources/OpenClip/Platform/HotkeyManager.swift)) resolves input synchronously, before presenting the focused palette:

1. **Warm selection:** reuse a valid `synchronousSelection(for: AppIdentity)` snapshot, including its rich input, generation and paste evidence. PID, app identity and the existing 30-second expiry apply.
2. **Clipboard fallback:** otherwise use `NSPasteboard.general` as captured at invocation, explicitly marked `.clipboard` so it cannot impersonate a live selection.
3. **Empty context:** otherwise open an empty palette for standalone actions.

In-flight passive selection work is cancelled before the field takes focus, so a late copy cannot land in the palette's own text field. The focused palette never starts an AX read or synthetic copy: the system-wide focused application is now OpenClip, and AX-reading its own SwiftUI hierarchy from the inspect queue trips SwiftUI's main-actor isolation checks. A cold copy-only app therefore shows its clipboard text (or an empty palette) rather than waiting for a fresh AX read.

Per-action hotkeys retain full retrieval/copy because they do not first focus a search field. The palette shows a read-only source indicator; it never switches inputs. Tab is reserved for future palette behavior and currently does nothing.

Passive selection monitoring continues even when "Appear Automatically" is disabled (`isAppEnabled == false` or `hotkeyOnly: true`), updating `latestSelection` and pre-warming the search index. Both passive mouse and keyboard paths withhold synthetic copy fallback under those settings; native AX reads still populate the cache. Monitoring is suppressed while the search palette owns keyboard input. The explicit hold gesture delivers straight from `handleMouseDown` and stays unaffected by `isAppEnabled`.

The hold's editable-field lookup runs off the main actor through `SelectionEditabilityProbe`,
bound to the original source PID and one `axReadTimeout` deadline. If the lookup times out,
clipboard fallback is refused; the UI thread keeps processing events.

## Privacy and non-destructive guarantees

- **No Clipboard Pollution (AX modes)**: `ax-text-control`, `ax-web-area`, and `browser-script` never write to `NSPasteboard`. They read the live accessibility tree or the browser's AppleScript bridge.
- **Copy modes are archive-and-restore**: `menu-copy`/`keyboard-copy` temporarily place the selected text on the general pasteboard, then restore the archived items tagged with the nspasteboard transient markers so clipboard managers don't treat the restore as a user copy.
- **Ignored Fields**: Secure text fields (such as password inputs or masked text areas) do not expose `kAXSelectedTextAttribute` through AX APIs, so their contents are not read.

## Inline action match context

Inline result evaluation receives the same per-action regex match context as click execution. The
selection remains available as `openclip.input.text`, while `openclip.input.matchedText` and
`openclip.input.captures` carry the regex match and capture groups. This lets inline actions such as
Currency Converter evaluate a value embedded in a longer selected passage.
