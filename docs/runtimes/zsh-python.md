# Executable Scripts Runtime (Zsh, Python, Bash)

The executable script action runtime ([`ScriptAction`](file:///Users/ganesh/dev/openclip/Sources/Core/Extensions/ScriptAction.swift)) allows OpenClip to execute external standalone script files (`.sh`, `.zsh`, `.py`, `.rb`, `.node`) located within extension packages or `~/.openclip/extensions/`.

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
 - `OPENCLIP_OPTION_<NAME>`: Configured extension option values.
3. **Pipes Setup**: Sets up `standardInput`, `standardOutput`, and `standardError` using `Pipe()`.
4. **Standard Input Delivery**: Selected text is written to `stdin` asynchronously.
5. **Process Exit Evaluation**: Ensures termination status is `0`. Non-zero exit status throws `NSError` containing `stderr` text.

---

## Environment Variables Matrix

| Environment Variable | Description |
| :--- | :--- |
| `OPENCLIP_TEXT` | Full text selected by the user. |
| `OPENCLIP_OPTION_<NAME>` | Value of extension option `<NAME>` (uppercase). |

---

## Output Processing: JSON vs Plain Text

`ScriptAction` evaluates output from `stdout` using a dual-mode parser:

### Mode 1: Structured JSON Output (`ScriptOutput`)

Scripts can return a JSON payload to specify explicit platform actions:

```json
{
 "type": "paste",
 "value": "Transformed text output"
}
```

Supported `type` values:
- `"paste"` $\rightarrow$ `ActionResult.paste(value)` (replaces selection in target application).
- `"copy"` $\rightarrow$ `ActionResult.copy(value)` (copies text to system clipboard).
- `"open_url"` $\rightarrow$ `ActionResult.openURL(URL)` (opens URL in default browser).

### Mode 2: Plain Text Output Fallback

If `stdout` contains non-JSON plain text, `ScriptAction` treats the raw output as replacement text and returns `ActionResult.paste(stdoutString)`.

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
