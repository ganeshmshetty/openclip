#!/bin/bash
# OpenClip Test Runner Script
# Usage: ./scripts/test.sh [core | all | TestClassName] [--verbose]
#   core          run the fast Core domain suite
#   all           run the full test suite
#   TestClassName run one test class (e.g. ActionRegistryTests)
#   --verbose     show the full xcodebuild and XCTest output

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
    -only-testing:OpenClipTests/NativeContentDetectorTests
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
    local group_total="$1"
    shift
    local extra_args=("$@")
    # Force tests to run in English (-testLanguage en) so hardcoded English assertions in the
    # suite are deterministic regardless of the host machine's locale (dev machines run zh-Hans;
    # CI runners are en). Without this, `String(localized:)` resolves per-locale and tests that
    # assert English copy fail outside English environments.
    local cmd=(xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' -testLanguage en "${extra_args[@]}" test)

    if [ "$VERBOSE" = true ]; then
        "${cmd[@]}"
    else
        local output_file
        output_file="$(mktemp "${TMPDIR:-/tmp}/openclip-tests.XXXXXX")"
        printf 'Running tests in %s groups. Use --verbose for full output.\n' "$group_total"

        if "${cmd[@]}" 2>&1 | tee "$output_file" | awk -v total="$group_total" '
            index($0, "Test Suite ") && index($0, " started at ") {
                suite = $0
                quote = sprintf("%c", 39)
                sub("^.*Test Suite " quote, "", suite)
                sub(quote ".*", "", suite)
                if (suite == "All tests" || suite ~ /\.xctest$/) next
                sub(/^.*\./, "", suite)
                if (!seen[suite]++) {
                    count++
                    printf "[%d/%d] %s\n", count, total, suite
                    fflush()
                }
            }
        '; then
            awk '/Executed [0-9]+ tests/ { summary = $0 }
                 /\*\* TEST SUCCEEDED \*\*/ { result = $0 }
                 END {
                     if (summary != "") print summary
                     if (result != "") print result
                     if (summary == "" && result == "") print "Test run finished."
                 }' "$output_file"
            rm -f "$output_file"
        else
            local status=$?
            printf '\nTest run failed. Relevant output:\n'
            awk '
                /Test Case .* failed/ { print; next }
                /\/Sources\/.*:[0-9]+: error:/ || /\/Tests\/.*:[0-9]+: error:/ { print; next }
                /\*\* BUILD FAILED \*\*/ || /\*\* TEST FAILED \*\*/ { print; next }
                /Executed [0-9]+ tests, with [1-9][0-9]* failures/ { summary = $0 }
                END { if (summary != "") print summary }
            ' "$output_file"
            printf '\nRun again with --verbose to see the complete build and test log.\n'
            rm -f "$output_file"
            return "$status"
        fi
    fi
}

if [ "$TEST_ARG" = "core" ]; then
    run_xcodebuild "${#CORE_TEST_FLAGS[@]}" "${CORE_TEST_FLAGS[@]}"
elif [ "$TEST_ARG" = "all" ] || [ -z "$TEST_ARG" ]; then
    TEST_GROUP_TOTAL="$(rg --no-filename -o 'class [A-Za-z0-9_]+Tests: XCTestCase' Tests/OpenClipTests \
        | sed -E 's/^class ([A-Za-z0-9_]+Tests): XCTestCase$/\1/' \
        | sort -u | wc -l | tr -d '[:space:]')"
    run_xcodebuild "$TEST_GROUP_TOTAL"
else
    if [[ "$TEST_ARG" == -* ]]; then
        printf 'Unknown option: %s\nUsage: ./scripts/test.sh [core | all | TestClassName] [--verbose]\n' "$TEST_ARG" >&2
        exit 2
    fi
    run_xcodebuild 1 -only-testing:OpenClipTests/"$TEST_ARG"
fi
