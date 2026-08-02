#!/bin/bash
# OpenClip Test Runner Script
# Usage: ./scripts/test.sh [TestClassName]

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

TEST_CLASS="$1"

if [ -n "$TEST_CLASS" ]; then
    echo "Running test class: $TEST_CLASS..."
    xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/$TEST_CLASS -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED|FAILED"
else
    echo "Running full test suite..."
    xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED|FAILED"
fi
