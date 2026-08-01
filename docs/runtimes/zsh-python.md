# Zsh & Python Executable Runtime

OpenClip supports local Unix subprocess scripts (`ScriptAction.swift` & `CustomAction.swift`). You can write scripts using Zsh (`/bin/zsh`), Python (`python3`), Ruby, Node.js, or compiled CLI binaries.

---

## Environment Variables & Stdin Data Stream

When executing shell or Python scripts, OpenClip passes the selected text in 2 ways:

1. **Environment Variables:** `POPCLIP_TEXT` and `OPENCLIP_TEXT` are injected into `ProcessInfo.environment`.
2. **Standard Input (`stdin`):** The text selection is streamed directly into the process `stdin`.

---

## Script Output Specifications

A shell or Python script can respond in 2 modes:

### Mode 1: Plain Text Output
Any text written to standard output (`stdout`) is captured. Depending on your action definition:
- Replaces selection (`replaceSelection: true`) via paste.
- Copies output to macOS Clipboard (`replaceSelection: false`).

### Mode 2: JSON Response Object
Write a JSON object to standard output (`stdout`) to explicitly control the action result:

```json
{
  "type": "paste",      // Options: "paste", "copy", "openURL"
  "value": "Formatted string content"
}
```

---

## Copy-Pasteable Zsh & Python Examples

### Example 1: Python Markdown Table Generator

Converts comma-separated or tab-separated text into a clean Markdown table.

```json
// openclip.json
{
  "Identifier": "com.openclip.markdownTable",
  "Name": "Markdown Table Generator",
  "Actions": [
    {
      "Title": "MD Table",
      "Icon": "symbol:tablecells",
      "Script": "main.py"
    }
  ]
}
```

```python
#!/usr/bin/env python3
# main.py
import sys
import os

text = sys.stdin.read().strip()
if not text:
    text = os.environ.get("POPCLIP_TEXT", "")

lines = [line.strip() for line in text.splitlines() if line.strip()]
if not lines:
    sys.exit(0)

# Parse rows
rows = [ [cell.strip() for cell in line.split(",")] for line in lines ]

# Format header & separator
header = rows[0]
separator = ["---"] * len(header)

table = []
table.append("| " + " | ".join(header) + " |")
table.append("| " + " | ".join(separator) + " |")

for row in rows[1:]:
    # Pad row if missing columns
    while len(row) < len(header):
        row.append("")
    table.append("| " + " | ".join(row[:len(header)]) + " |")

output_table = "\n".join(table)
print(output_table)
```

---

### Example 2: Zsh Base64 Encoder / Decoder

Encodes or decodes text using standard Unix `base64`.

```json
// openclip.json
{
  "Identifier": "com.openclip.base64tool",
  "Name": "Base64 Encoder",
  "Actions": [
    {
      "Title": "Base64 Encode",
      "Icon": "symbol:lock",
      "Script": "encode.sh"
    }
  ]
}
```

```bash
#!/bin/zsh
# encode.sh
# Read from env var or stdin
INPUT="${POPCLIP_TEXT}"
if [ -z "$INPUT" ]; then
    INPUT=$(cat -)
fi

ENCODED=$(echo -n "$INPUT" | base64)

# Return JSON result to instruct OpenClip to paste formatted result
cat <<EOF
{
  "type": "paste",
  "value": "${ENCODED}"
}
EOF
```

---

### Example 3: Python Code Explain API Caller

Sends selected code snippet to an API endpoint for instant explanation.

```python
#!/usr/bin/env python3
# main.py
import sys
import json
import urllib.request

code_text = sys.stdin.read()

payload = {
    "model": "gpt-4o-mini",
    "messages": [
        {"role": "system", "content": "Explain the following code concisely in 2 sentences."},
        {"role": "user", "content": code_text}
    ]
}

# Output result via structured JSON
result = {
    "type": "copy",
    "value": "Code explanation copied!"
}
print(json.dumps(result))
```
