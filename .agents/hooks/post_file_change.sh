#!/bin/bash
# .agents/hooks/post_file_change.sh
# Sensible post-edit hook: auto-generates Xcode project if Swift files were changed.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Run xcodegen silently in background if xcodegen is installed
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null 2>&1 || true
fi

echo '{"decision": "allow"}'
