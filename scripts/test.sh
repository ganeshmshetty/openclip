#!/bin/bash
# OpenClip Test Runner Script
# Usage: ./scripts/test.sh [--unit | TestClassName]
#   --unit        run the unit suite (skips live-integration tests)
#   TestClassName run a single test class (e.g. ActionRegistryTests)

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

TEST_ARG="$1"

SKIP_INTEGRATION_FLAGS=(
    -skip-testing:OpenClipTests/TextRetrieverTests
    -skip-testing:OpenClipTests/KeychainActionOptionStoreTests
    -skip-testing:OpenClipTests/ScriptActionExecutionTests
    -skip-testing:OpenClipTests/ActionResultHandlerTests
    -skip-testing:OpenClipTests/CanvasEndToEndTests
)

if [ "$TEST_ARG" = "--unit" ]; then
    echo "Running unit test suite (skipping live-integration tests)..."
    xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' "${SKIP_INTEGRATION_FLAGS[@]}" test | grep -E "Test Suite|passed|failed|SUCCEEDED|FAILED"
elif [ -n "$TEST_ARG" ]; then
    echo "Running test class: $TEST_ARG..."
    xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/$TEST_ARG -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED|FAILED"
else
    echo "Running full test suite..."
    xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED|FAILED"
fi

