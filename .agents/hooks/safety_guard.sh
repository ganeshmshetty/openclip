#!/bin/bash
# .agents/hooks/safety_guard.sh
# Sensible safety guardrail for shell command execution.

input_json=$(cat)

# Extract command line from JSON input using python3 (dependency-free)
command_line=$(python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    args = data.get('toolCall', {}).get('args', {})
    print(args.get('CommandLine') or data.get('tool_input', {}).get('command') or '')
except Exception:
    print('')
" <<< "$input_json")

# Block dangerous root deletions or forced main branch overwrites
if [[ "$command_line" =~ rm[[:space:]]+-rf[[:space:]]+(/|~|\*) ]] || [[ "$command_line" =~ git[[:space:]]+push[[:space:]]+.*--force.*main ]]; then
    echo '{"decision": "deny", "reason": "Blocked dangerous command execution."}'
    exit 0
fi

# Ask for confirmation on hard resets
if [[ "$command_line" =~ git[[:space:]]+reset[[:space:]]+--hard ]]; then
    echo '{"decision": "ask", "reason": "git reset --hard will discard uncommitted changes."}'
    exit 0
fi

echo '{"decision": "allow"}'
