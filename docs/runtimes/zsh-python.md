# Executable Scripts Runtime (Zsh, Python, Bash)

The executable script action runtime ([`ScriptAction`](../../Sources/Core/Extensions/ScriptAction.swift)) allows OpenClip to execute external standalone script files (`.sh`, `.zsh`, `.py`, `.rb`, `.node`) located within extension packages or `~/.openclip/extensions/`.

---

## Process Execution Lifecycle

```
Selection Context ---> Process Instance ---> Inject Environment & write stdin
 |
 v
 Script Execution (Zsh/Python)
 |
 v
 Read stdout & JSON / Text Output
 |
 v
 ActionResult (.paste / .copy / .openURL)
```

1. **Executable Check**: `ScriptAction` checks `FileManager.default.isExecutableFile(atPath:)`.
2. **Environment Injection**:
 - `OPENCLIP_TEXT`: Selected text string.
 - `OPENCLIP_MATCHED`, `OPENCLIP_CAPTURE_N`, `OPENCLIP_BUNDLE_ID`, `OPENCLIP_ACTION_ID` (see the matrix below).
3. **Pipes Setup**: Sets up `standardInput`, `standardOutput`, and `standardError` using `Pipe()`.
4. **Standard Input Delivery**: Selected text is written to `stdin` asynchronously.
5. **Timeout Watchdog**: A detached task terminates the process if it exceeds `Constants.scriptTimeout` (60 s), so a hanging script never leaves the popup spinning. Users can also abort running loading tasks anytime by clicking the loading toast. Any new action that spawns a subprocess must implement the same watchdog.
6. **Process Exit Evaluation**: Ensures termination status is `0`. Non-zero exit status throws `NSError` containing `stderr` text.

---

## Environment Variables Matrix

| Environment Variable | Description |
| :--- | :--- |
| `OPENCLIP_TEXT` | Full text selected by the user. |
| `OPENCLIP_HTML` | HTML markup of the selection (if captured). |
| `OPENCLIP_RTF` | RTF markup of the selection (if captured). |
| `OPENCLIP_MATCHED` | Text matched by the action's regex (falls back to the full selection). |
| `OPENCLIP_CAPTURE_N` | Regex capture group `N` (1-based), one per group. |
| `OPENCLIP_BUNDLE_ID` | Bundle identifier of the frontmost/source app. |
| `OPENCLIP_ACTION_ID` | The action's identifier. |

The selected text is also written to the subprocess's `stdin`. Extension *options* are not injected
as environment variables; read them from stdin or resolve them on the OpenClip side.

## Output Processing: JSON vs Plain Text

`ScriptAction` evaluates output from `stdout` via `ShellResultMapper` using a dual-mode parser:

### Mode 1: Structured JSON Output (`ScriptJSONOutput`)

Scripts can return a JSON payload to specify explicit platform actions:

```json
{
  "type": "paste",
  "value": "Transformed text output"
}
```

Supported `type` values:
- `"paste"` → `ActionResult.paste(value)` (replaces selection in target application).
- `"copy"` → `ActionResult.copy(value)` (copies text to system clipboard).
- `"pasteContent"` / `"paste-content"` → `ActionResult.pasteContent` (rich multi-type paste; fields: `value` = plain text, `html`, `rtf`).
- `"copyContent"` / `"copy-content"` → `ActionResult.copyContent` (rich multi-type copy; same fields as `"pasteContent"`).
- `"cut"` → `ActionResult.cut(value)` (copies text and sends backspace delete event).
- `"openURL"` / `"url"` → `ActionResult.openURL(URL)` (opens URL in default browser; URL parsed from `value`).
- `"keyPress"` / `"keypress"` → `ActionResult.keyPress(KeyPressSpec)` (`key`, `modifiers: ["command", "shift", ...]`).
- `"runShortcut"` / `"shortcut"` → `ActionResult.runShortcut(name:input:)` (`name`/`shortcutName`, `input`/`value`).
- `"notify"` / `"notification"` → `ActionResult.notify(title:body:)` (`title`, `body`/`message`).
- `"shareService"` / `"share"` → `ActionResult.shareService(identifier:text:)` (`identifier` required, `value`/`input`).
- `"sequence"` → `ActionResult.sequence([ActionResult])` (`actions: [ScriptJSONOutput]`).
- `"fail"` / `"failure"` / `"error"` → surfaces error toast (`message`/`reason`/`value`).
- `"toast"` → `ActionResult.toast` (`message`, `style`: `"success"`/`"error"`/`"info"`, `keepVisible` optional, default `false`).
- `"configure"` → `ActionResult.openConfiguration` (`reason`, `missing: [optionID]`).

`"showContent"` is **not** accepted — a decoded-but-unknown `type` maps to `.success`.

### Mode 2: Plain Text Output Fallback

If `stdout` contains non-JSON plain text, `ScriptAction` treats the raw output as implicitly
returned text and returns `ActionResult.text(stdoutString)` — delivered per the user's per-click
preference (preview/paste/copy).

---

## Practical Examples

### Python Script Example (`clean_markdown.py`)

```python
#!/usr/bin/env python3
import sys, os, re

# Read input from stdin or environment
text = sys.stdin.read() or os.environ.get("OPENCLIP_TEXT", "")

# Remove markdown links, leaving plain text
clean_text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)

# Print result to stdout
sys.stdout.write(clean_text)
```

### Zsh Shell Script Example (`uppercase.sh`)

```bash
#!/bin/zsh
echo "$OPENCLIP_TEXT" | tr '[:lower:]' '[:upper:]'
```
