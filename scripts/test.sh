#!/bin/bash
# OpenClip Test Runner Script
# Usage: ./scripts/test.sh [--unit | TestClassName]
#   --unit        run the unit suite (skips live-integration tests)
#   TestClassName run a single test class (e.g. ActionRegistryTests)

set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

TEST_ARG="${1:-}"
VERBOSE=false

if [ "$TEST_ARG" = "--verbose" ] || [ "${2:-}" = "--verbose" ]; then
    VERBOSE=true
    if [ "$TEST_ARG" = "--verbose" ]; then
        TEST_ARG="${2:-}"
    fi
fi

CORE_TEST_FLAGS=(
    -only-testing:OpenClipTests/ValidateExpressionTests
    -only-testing:OpenClipTests/SemanticVersionTests
    -only-testing:OpenClipTests/CalculateActionTests
    -only-testing:OpenClipTests/ManifestValidationTests
    -only-testing:OpenClipTests/TextSanitizerTests
    -only-testing:OpenClipTests/TextPlaceholderEngineTests
    -only-testing:OpenClipTests/SettingsStoreTests
    -only-testing:OpenClipTests/RuleEngineTests
    -only-testing:OpenClipTests/DebugLogBufferTests
    -only-testing:OpenClipTests/DebugLogEntryTests
    -only-testing:OpenClipTests/DebugLogFilterTests
    -only-testing:OpenClipTests/DebugLogStoreTests
    -only-testing:OpenClipTests/AppFilterTests
    -only-testing:OpenClipTests/ContextualFilteringTests
    -only-testing:OpenClipTests/ExtensionManifestTests
    -only-testing:OpenClipTests/ExtensionRiskProfileTests
    -only-testing:OpenClipTests/ExtensionTrustStateTests
    -only-testing:OpenClipTests/ExtensionPackageHashResolverTests
    -only-testing:OpenClipTests/ExtensionUpdatePlannerTests
)

run_xcodebuild() {
    local extra_args=("$@")
    local cmd=(xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' "${extra_args[@]}" test)

    if [ "$VERBOSE" = true ]; then
        "${cmd[@]}"
    elif command -v xcbeautify >/dev/null 2>&1; then
        if [ -n "${GITHUB_ACTIONS:-}" ]; then
            "${cmd[@]}" 2>&1 | xcbeautify --renderer github-actions --is-ci
        else
            "${cmd[@]}" 2>&1 | xcbeautify
        fi
    else
        # Fallback filter that retains test suites, test cases, passes, failures, assertion error lines, and final status
        "${cmd[@]}" 2>&1 | grep -E "Test Suite|Test Case|passed|failed|failure|error:|SUCCEEDED|FAILED|\*\*"
    fi
}

if [ "$TEST_ARG" = "core" ]; then
    echo "Running Core domain test suite..."
    run_xcodebuild "${CORE_TEST_FLAGS[@]}"
elif [ "$TEST_ARG" = "--unit" ] || [ "$TEST_ARG" = "all" ] || [ -z "$TEST_ARG" ]; then
    echo "Running full test suite (0 skips)..."
    run_xcodebuild
else
    echo "Running test class: $TEST_ARG..."
    run_xcodebuild -only-testing:OpenClipTests/"$TEST_ARG"
fi

